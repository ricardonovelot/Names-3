import Foundation
import Photos
import AVFoundation
import os
import os.signpost
import QuartzCore

actor VideoPrefetchStore {
    private let cache = NSCache<NSString, AVAsset>()
    private var inFlight: [String: PHImageRequestID] = [:]
    private var waiters: [String: [UUID: CheckedContinuation<AVAsset?, Never>]] = [:]
    private var backoffUntil: [String: Date] = [:]

    private var cachedKeys = Set<String>()

    private var spActorToRequest: [String: OSSignpostID] = [:]
    private var spRequestToResult: [String: OSSignpostID] = [:]

    init() {
        cache.countLimit = 120
    }

    func stats() -> (inFlight: Int, cached: Int, waiters: Int) {
        let totalWaiters = waiters.values.reduce(0) { $0 + $1.count }
        return (inFlight.count, cachedKeys.count, totalWaiters)
    }

    private func logQueueDepth(reason: String, id: String?) {
        let totalWaiters = waiters.values.reduce(0) { $0 + $1.count }
        Diagnostics.videoPerf("Prefetch(AVAsset) queueDepth reason=\(reason) id=\(id ?? "nil") inFlight=\(inFlight.count) totalWaiters=\(totalWaiters) cache≈\(cachedKeys.count)")
    }

    func assetIfCached(_ id: String) -> AVAsset? {
        cache.object(forKey: id as NSString)
    }

    func prefetch(_ assets: [PHAsset]) async {
        if let firstTarget = assets.first?.localIdentifier {
            Task { @MainActor in
                FirstLaunchProbe.shared.prefetchActorEnter(id: firstTarget)
            }
        }

        for asset in assets {
            let id = asset.localIdentifier

            Diagnostics.log("Prefetcher(actor) enqueue id=\(id)")

            if cache.object(forKey: id as NSString) != nil {
                Diagnostics.log("Prefetcher(actor) already cached id=\(id)")
                continue
            }
            if inFlight[id] != nil { continue }
            if let until = backoffUntil[id], until > Date() {
                Task { @MainActor in
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

            var spAR = spActorToRequest[id]
            Diagnostics.signpostBegin("PrefetchActorToRequestCall", id: &spAR)
            spActorToRequest[id] = spAR

            Task { @MainActor in
                FirstLaunchProbe.shared.prefetchRequestCall(id: id)
            }

            let reqID = PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, info in
                Task {
                    await self?.handleResult(id: id, avAsset: avAsset, info: info)
                }
            }

            inFlight[id] = reqID
            logQueueDepth(reason: "start", id: id)

            if let sid = spActorToRequest.removeValue(forKey: id) {
                Diagnostics.signpostEnd("PrefetchActorToRequestCall", id: sid)
            }
            var spRS = spRequestToResult[id]
            Diagnostics.signpostBegin("PrefetchRequestCallToStart", id: &spRS)
            spRequestToResult[id] = spRS

            Diagnostics.log("Prefetcher(actor) started id=\(id) reqID=\(reqID)")
            Task { @MainActor in
                NotificationCenter.default.post(name: .videoPrefetcherDidStart, object: nil, userInfo: ["id": id, "reqID": reqID])
                Diagnostics.log("Prefetcher started id=\(id) reqID=\(reqID)")
                FirstLaunchProbe.shared.prefetchStarted(id: id)
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
                logQueueDepth(reason: "cancel", id: id)
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
            cachedKeys.remove(id)
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

        if let sid = spRequestToResult.removeValue(forKey: id) {
            Diagnostics.signpostEnd("PrefetchRequestCallToStart", id: sid)
        }

        await MainActor.run {
            NotificationCenter.default.post(name: .videoPrefetcherDidFinish, object: nil, userInfo: ["id": id, "success": avAsset != nil])
        }

        if let avAsset {
            cache.setObject(avAsset, forKey: id as NSString)
            cachedKeys.insert(id)
            // CLEAR: success cancels backoff
            backoffUntil[id] = nil
            await MainActor.run {
                if let info {
                    let inCloud = (info[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue ?? false
                    let cancelled = (info[PHImageCancelledKey] as? NSNumber)?.boolValue == true
                    let errorDesc = (info[PHImageErrorKey] as? NSError)?.localizedDescription
                    let assetKind = String(describing: type(of: avAsset))
                    var scheme = "n/a"
                    if let urlAsset = avAsset as? AVURLAsset {
                        scheme = urlAsset.url.scheme ?? "nil"
                    }
                    Diagnostics.log("Prefetcher result id=\(id) kind=\(assetKind) urlScheme=\(scheme) inCloud=\(inCloud) cancelled=\(cancelled) error=\(String(describing: errorDesc))")
                } else {
                    Diagnostics.log("Prefetcher result id=\(id) info=nil")
                }
                Diagnostics.log("Prefetcher cached asset id=\(id)")
                DownloadTracker.shared.updateProgress(for: id, phase: .prefetch, progress: 1.0)
                NotificationCenter.default.post(name: .videoPrefetcherDidCacheAsset, object: nil, userInfo: ["id": id])
                FirstLaunchProbe.shared.prefetchCached(id: id)
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
        logQueueDepth(reason: "finish", id: id)
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

    func stats() async -> (inFlight: Int, cached: Int, waiters: Int) {
        await store.stats()
    }

    func prefetch(_ assets: [PHAsset]) {
        if let firstTarget = assets.first?.localIdentifier, FirstLaunchProbe.shared.firstAssetID == firstTarget {
            FirstLaunchProbe.shared.prefetchEnqueue(id: firstTarget)
        }
        Diagnostics.log("Prefetcher facade call onMain=\(Thread.isMainThread)")

        var spEA: OSSignpostID?
        Diagnostics.signpostBegin("PrefetchEnqueueToActor", id: &spEA)
        let t0 = CACurrentMediaTime()

        Task {
            // Complete Enqueue->Actor timing
            let dt = CACurrentMediaTime() - t0
            Diagnostics.log("Prefetcher(actor) enter dt(Enqueue→Actor)=\(String(format: "%.3f", dt))s")
            Diagnostics.signpostEnd("PrefetchEnqueueToActor", id: spEA)
            await store.prefetch(assets)
        }
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