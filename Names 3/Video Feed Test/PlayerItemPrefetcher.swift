import Foundation
import Photos
import AVFoundation
import os
import os.signpost

/// Wraps Photos info dict for use in @Sendable closures (Swift 6).
private struct SendableInfo: @unchecked Sendable {
    let value: [AnyHashable: Any]?
}

actor PlayerItemPrefetchStore {
    private let cache = NSCache<NSString, AVPlayerItem>()
    private var inFlight: [String: PHImageRequestID] = [:]
    private var waiters: [String: [UUID: CheckedContinuation<AVPlayerItem?, Never>]] = [:]

    private var cachedKeys = Set<String>()
    private var pending: [PHAsset] = []
    private var pendingIds = Set<String>()

    private var spRequestToFinish: [String: OSSignpostID] = [:]

    /// Limits concurrent requestPlayerItem calls to reduce FigFilePlayer -12860/-12780 burst and HALC overload.
    private var maxConcurrent: Int {
        #if targetEnvironment(simulator)
        2
        #else
        3
        #endif
    }

    init() {
        cache.countLimit = 24
    }
    
    func stats() -> (inFlight: Int, cached: Int, waiters: Int) {
        let totalWaiters = waiters.values.reduce(0) { $0 + $1.count }
        return (inFlight.count, cachedKeys.count, totalWaiters)
    }
    
    private func logQueueDepth(reason: String, id: String?) {
        let totalWaiters = waiters.values.reduce(0) { $0 + $1.count }
        Diagnostics.videoPerf("Prefetch(PlayerItem) queueDepth reason=\(reason) id=\(id ?? "nil") inFlight=\(inFlight.count) totalWaiters=\(totalWaiters) cache≈\(cachedKeys.count)")
    }
    
    func prefetch(_ assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }
        for asset in assets {
            let id = asset.localIdentifier
            if cache.object(forKey: id as NSString) != nil { continue }
            if inFlight[id] != nil { continue }
            if pendingIds.contains(id) { continue }

            Diagnostics.log("PlayerItemPrefetcher(actor) enqueue id=\(id)")
            pending.append(asset)
            pendingIds.insert(id)
        }
        await processQueue()
    }

    private func processQueue() async {
        while inFlight.count < maxConcurrent, let asset = pending.first {
            let id = asset.localIdentifier
            pending.removeFirst()
            pendingIds.remove(id)

            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
            options.progressHandler = { progress, _, _, _ in
                Task { @MainActor in
                    DownloadTracker.shared.updateProgress(for: id, phase: .playerItem, progress: progress)
                }
            }

            var spRF = spRequestToFinish[id]
            Diagnostics.signpostBegin("PlayerItemPrefetchRequestToFinish", id: &spRF)
            spRequestToFinish[id] = spRF

            let reqID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, info in
                let wrapped = SendableInfo(value: info)
                Task { [weak self] in
                    await self?.handleResult(id: id, item: item, info: wrapped.value)
                }
            }
            inFlight[id] = reqID
            logQueueDepth(reason: "start", id: id)

            Diagnostics.log("PlayerItemPrefetcher(actor) started id=\(id) reqID=\(reqID)")
            await MainActor.run {
                Diagnostics.log("PlayerItemPrefetcher started id=\(id) reqID=\(reqID)")
                NotificationCenter.default.post(name: .playerItemPrefetcherDidStart, object: nil, userInfo: ["id": id, "reqID": reqID])
            }
        }
    }
    
    func cancel(_ assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }
        let manager = PHImageManager.default()
        for asset in assets {
            let id = asset.localIdentifier
            pending.removeAll { $0.localIdentifier == id }
            pendingIds.remove(id)
            if let req = inFlight.removeValue(forKey: id) {
                manager.cancelImageRequest(req)
                await MainActor.run {
                    Diagnostics.log("PlayerItemPrefetcher cancelled id=\(id) reqID=\(req)")
                }
                logQueueDepth(reason: "cancel", id: id)
            }
            // Wake waiters with nil
            if var dict = waiters.removeValue(forKey: id) {
                for (_, cont) in dict { cont.resume(returning: nil) }
                dict.removeAll()
            }
            // Drop cached item to free memory
            cache.removeObject(forKey: id as NSString)
            cachedKeys.remove(id)
        }
        await processQueue()
    }
    
    // Returns a prefetched item if present or waits up to timeout for an in-flight request.
    // On success, "takes" the item from cache so it won't be reused concurrently.
    func item(for id: String, timeout: Duration) async -> AVPlayerItem? {
        if let cached = cache.object(forKey: id as NSString) {
            cache.removeObject(forKey: id as NSString)
            return cached
        }
        guard inFlight[id] != nil else {
            return nil
        }
        
        let waiterID = UUID()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (cont: CheckedContinuation<AVPlayerItem?, Never>) in
                Task {
                    await registerWaiter(for: id, waiterID: waiterID, continuation: cont)
                    Task {
                        try? await Task.sleep(for: timeout)
                        await timeoutWaiter(for: id, waiterID: waiterID)
                    }
                }
            }
        }, onCancel: {
            Task { await self.cancelWaiter(for: id, waiterID: waiterID) }
        })
    }
    
    private func registerWaiter(for id: String, waiterID: UUID, continuation: CheckedContinuation<AVPlayerItem?, Never>) async {
        var dict = waiters[id] ?? [:]
        dict[waiterID] = continuation
        waiters[id] = dict
    }
    
    private func timeoutWaiter(for id: String, waiterID: UUID) async {
        guard let dict = waiters[id] else { return }
        var mutable = dict
        if let cont = mutable.removeValue(forKey: waiterID) {
            waiters[id] = mutable.isEmpty ? nil : mutable
            cont.resume(returning: nil)
        }
    }
    
    private func cancelWaiter(for id: String, waiterID: UUID) async {
        guard let dict = waiters[id] else { return }
        var mutable = dict
        if let cont = mutable.removeValue(forKey: waiterID) {
            waiters[id] = mutable.isEmpty ? nil : mutable
            cont.resume(returning: nil)
        }
    }
    
    private func handleResult(id: String, item: AVPlayerItem?, info: [AnyHashable: Any]?) async {
        StorageMonitor.reportIfCloudPhotoLowStorage(info: info)
        inFlight.removeValue(forKey: id)
        
        if let sid = spRequestToFinish.removeValue(forKey: id) {
            Diagnostics.signpostEnd("PlayerItemPrefetchRequestToFinish", id: sid)
        }

        // If there are waiters, deliver directly and do not cache.
        // AVPlayerItem can only be associated with one AVPlayer—give to first waiter only; rest get nil.
        if let waitersForId = waiters.removeValue(forKey: id) {
            let consumers = Array(waitersForId.values)
            if let item, let first = consumers.first {
                first.resume(returning: item)
                for cont in consumers.dropFirst() {
                    cont.resume(returning: nil)
                }
            } else {
                for cont in consumers {
                    cont.resume(returning: nil)
                }
            }
        } else if let item {
            cache.setObject(item, forKey: id as NSString)
            cachedKeys.insert(id)
        }
        
        let wrappedInfo = SendableInfo(value: info)
        await MainActor.run {
            PhotoKitDiagnostics.logResultInfoIfNotable(prefix: "PlayerItemPrefetcher result", info: wrappedInfo.value)
            NotificationCenter.default.post(name: .playerItemPrefetcherDidFinish, object: nil, userInfo: ["id": id, "success": item != nil])
            if item != nil {
                DownloadTracker.shared.updateProgress(for: id, phase: .playerItem, progress: 1.0)
            }
        }
        logQueueDepth(reason: "finish", id: id)
        await processQueue()
    }
}

@MainActor
final class PlayerItemPrefetcher {
    static let shared = PlayerItemPrefetcher()
    private let store = PlayerItemPrefetchStore()
    
    func stats() async -> (inFlight: Int, cached: Int, waiters: Int) {
        await store.stats()
    }
    
    func prefetch(_ assets: [PHAsset]) {
        Task { await store.prefetch(assets) }
    }
    
    func cancel(_ assets: [PHAsset]) {
        Task { await store.cancel(assets) }
    }
    
    func item(for id: String, timeout: Duration) async -> AVPlayerItem? {
        await store.item(for: id, timeout: timeout)
    }
}
