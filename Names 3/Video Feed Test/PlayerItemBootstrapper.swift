import Foundation
import Photos
import AVFoundation
import QuartzCore

actor PlayerItemBootstrapper {
    static let shared = PlayerItemBootstrapper()

    private var tasks: [String: Task<(AVPlayerItem?, [AnyHashable: Any]?), Never>] = [:]

    func ensureStarted(asset: PHAsset) {
        let id = asset.localIdentifier
        guard tasks[id] == nil else { return }
        let t0 = CACurrentMediaTime()
        Diagnostics.video("[Bootstrap] ensureStarted id=\(id)")
        tasks[id] = Task { [weak self] in
            // Phase-gate to appActive to avoid heavy subsystems before the app is active.
            let ok = await PhaseGate.shared.waitUntil(.appActive, timeout: 30)
            Diagnostics.video("[Bootstrap] gate appActive ok=\(ok) id=\(id) dt=\(String(format: "%.3f", CACurrentMediaTime() - t0))s")

            if Task.isCancelled { return (nil, nil) }

            let options = PHVideoRequestOptions()
            options.deliveryMode = .mediumQualityFormat
            options.isNetworkAccessAllowed = true
            options.progressHandler = { progress, _, _, _ in
                Task { @MainActor in
                    DownloadTracker.shared.updateProgress(for: id, phase: .playerItem, progress: progress)
                }
            }

            let result: (AVPlayerItem?, [AnyHashable: Any]?) = await withCheckedContinuation { (cont: CheckedContinuation<(AVPlayerItem?, [AnyHashable: Any]?), Never>) in
                let reqID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, info in
                    cont.resume(returning: (item, info))
                }
                Diagnostics.video("[Bootstrap] requestPlayerItem started id=\(id) reqID=\(reqID)")
            }
            return result
        }
    }

    func awaitResult(asset: PHAsset) async -> (AVPlayerItem?, [AnyHashable: Any]?) {
        let id = asset.localIdentifier
        if tasks[id] == nil {
            ensureStarted(asset: asset)
        }
        let res = await tasks[id]?.value ?? (nil, nil)
        return res
    }

    func cancel(id: String) {
        if let t = tasks.removeValue(forKey: id) {
            t.cancel()
            Diagnostics.video("[Bootstrap] cancel id=\(id)")
        }
    }
}