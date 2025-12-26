import Foundation
import Photos
import AVFoundation

actor VideoPrefetchStore {
    private let cache = NSCache<NSString, AVAsset>()
    private var inFlight: [String: PHImageRequestID] = [:]
    private var waiters: [String: [UUID: CheckedContinuation<AVAsset?, Never>]] = [:]
    private var backoffUntil: [String: Date] = [:]

    init() {
        cache.countLimit = 120
    }

    func assetIfCached(_ id: String) -> AVAsset? {
        cache.object(forKey: id as NSString)
    }

    func prefetch(_ assets: [PHAsset]) async {
        for asset in assets {
            let id = asset.localIdentifier
            if cache.object(forKey: id as NSString) != nil { continue }
            if inFlight[id] != nil { continue }
            if let until = backoffUntil[id], until > Date() {
                await MainActor.run {
                    let remaining = until.timeIntervalSinceNow
                    Diagnostics.log("Prefetcher backoff id=\(id) remaining=\(String(format: "%.1f", max(0, remaining)))s")
                }
                continue
            }

            let options = PHVideoRequestOptions()
            options.deliveryMode = .mediumQualityFormat
            options.isNetworkAccessAllowed = true
            options.progressHandler = { progress, _, _, _ in
                Task { @MainActor in
                    DownloadTracker.shared.updateProgress(for: id, phase: .prefetch, progress: progress)
                }
            }

            let reqID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, info in
                Task {
                    await self?.handleResult(id: id, avAsset: avAsset, info: info)
                }
            }
            inFlight[id] = reqID
            await MainActor.run {
                Diagnostics.log("Prefetcher started id=\(id) reqID=\(reqID)")
            }
        }
    }

    func cancel(_ assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }
        let manager = PHImageManager.default()
        for asset in assets {
            let id = asset.localIdentifier
            if let req = inFlight.removeValue(forKey: id) {
                manager.cancelImageRequest(req)
                await MainActor.run {
                    Diagnostics.log("Prefetcher cancelled id=\(id) reqID=\(req)")
                }
                // Notify any waiters with nil (cancelled)
                if var dict = waiters.removeValue(forKey: id) {
                    for (_, cont) in dict {
                        cont.resume(returning: nil)
                    }
                    dict.removeAll()
                }
            }
        }
    }

    func removeCached(for ids: [String]) {
        for id in ids {
            cache.removeObject(forKey: id as NSString)
        }
    }

    // Await a cached or in-flight asset up to a timeout. Returns nil on timeout/miss.
    func asset(for id: String, timeout: Duration) async -> AVAsset? {
        if let cached = cache.object(forKey: id as NSString) {
            return cached
        }
        guard inFlight[id] != nil else {
            return nil
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            Task { await self.cancelWaiter(for: id, waiterID: waiterID) }
        } operation: {
            await withCheckedContinuation { (cont: CheckedContinuation<AVAsset?, Never>) in
                Task {
                    await registerWaiter(for: id, waiterID: waiterID, continuation: cont)
                    Task {
                        try? await Task.sleep(for: timeout)
                        await timeoutWaiter(for: id, waiterID: waiterID)
                    }
                }
            }
        }
    }

    private func registerWaiter(for id: String, waiterID: UUID, continuation: CheckedContinuation<AVAsset?, Never>) {
        var dict = waiters[id] ?? [:]
        dict[waiterID] = continuation
        waiters[id] = dict
    }

    private func timeoutWaiter(for id: String, waiterID: UUID) {
        guard var dict = waiters[id] else { return }
        if let cont = dict.removeValue(forKey: waiterID) {
            waiters[id] = dict.isEmpty ? nil : dict
            cont.resume(returning: nil)
        }
    }

    private func cancelWaiter(for id: String, waiterID: UUID) {
        guard var dict = waiters[id] else { return }
        if let cont = dict.removeValue(forKey: waiterID) {
            waiters[id] = dict.isEmpty ? nil : dict
            cont.resume(returning: nil)
        }
    }

    private func handleResult(id: String, avAsset: AVAsset?, info: [AnyHashable: Any]?) async {
        inFlight.removeValue(forKey: id)
        if let avAsset {
            cache.setObject(avAsset, forKey: id as NSString)
            // CLEAR: success cancels backoff
            backoffUntil[id] = nil
            await MainActor.run {
                Diagnostics.log("Prefetcher cached asset id=\(id)")
                // Do not mark playback complete here; prefetch done != playback ready
                DownloadTracker.shared.updateProgress(for: id, phase: .prefetch, progress: 1.0)
                NotificationCenter.default.post(name: .videoPrefetcherDidCacheAsset, object: nil, userInfo: ["id": id])
            }
        } else {
            // evaluate error
            let nsErr = info?[PHImageErrorKey] as? NSError
            let cancelled = (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true
            let isTransientCloud = (nsErr?.domain == "CloudPhotoLibraryErrorDomain" && nsErr?.code == 1005)
            if isTransientCloud {
                backoffUntil[id] = Date().addingTimeInterval(10)
            }
            await MainActor.run {
                PhotoKitDiagnostics.logResultInfo(prefix: "Prefetcher AVAsset nil", info: info)
                if !cancelled && !isTransientCloud {
                    DownloadTracker.shared.markFailed(id: id, note: nsErr?.localizedDescription)
                }
            }
        }
        if var dict = waiters.removeValue(forKey: id) {
            for (_, cont) in dict {
                cont.resume(returning: avAsset)
            }
            dict.removeAll()
        }
    }
}

@MainActor
final class VideoPrefetcher {
    static let shared = VideoPrefetcher()
    private let store = VideoPrefetchStore()

    func prefetch(_ assets: [PHAsset]) {
        Task { await store.prefetch(assets) }
    }

    func cancel(_ assets: [PHAsset]) {
        Task { await store.cancel(assets) }
    }

    func removeCached(for ids: [String]) {
        Task { await store.removeCached(for: ids) }
    }

    func asset(for id: String, timeout: Duration) async -> AVAsset? {
        await store.asset(for: id, timeout: timeout)
    }

    func assetIfCached(_ id: String) async -> AVAsset? {
        await store.assetIfCached(id)
    }
}