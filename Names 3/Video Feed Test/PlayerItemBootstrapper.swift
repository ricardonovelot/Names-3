import Foundation
import Photos
import AVFoundation
import QuartzCore

/// Wraps Photos/AVFoundation types for use across actor boundaries (Swift 6).
private struct PlayerItemResult: @unchecked Sendable {
    let item: AVPlayerItem?
    let info: [AnyHashable: Any]?
}

actor PlayerItemBootstrapper {
    static let shared = PlayerItemBootstrapper()

    private var tasks: [String: Task<PlayerItemResult, Never>] = [:]

    func ensureStarted(asset: PHAsset) {
        let id = asset.localIdentifier
        guard tasks[id] == nil else { return }
        let t0 = CACurrentMediaTime()
        Diagnostics.video("[Bootstrap] ensureStarted id=\(id)")
        tasks[id] = Task {
            // Phase-gate to appActive to avoid heavy subsystems before the app is active.
            let ok = await PhaseGate.shared.waitUntil(.appActive, timeout: 30)
            Diagnostics.video("[Bootstrap] gate appActive ok=\(ok) id=\(id) dt=\(String(format: "%.3f", CACurrentMediaTime() - t0))s")

            if Task.isCancelled { return PlayerItemResult(item: nil, info: nil) }

            let options = PHVideoRequestOptions()
            // .automatic lets the system optimize for streaming (like Apple Photos); .mediumQualityFormat triggers FIGSANDBOX -17507 with iCloud videos
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
            options.progressHandler = { progress, _, _, _ in
                Task { @MainActor in
                    DownloadTracker.shared.updateProgress(for: id, phase: .playerItem, progress: progress)
                }
            }

            let result = await withCheckedContinuation { (cont: CheckedContinuation<PlayerItemResult, Never>) in
                let reqID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, info in
                    cont.resume(returning: PlayerItemResult(item: item, info: info))
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
        let res = await tasks[id]?.value ?? PlayerItemResult(item: nil, info: nil)
        return (res.item, res.info)
    }

    func cancel(id: String) {
        if let t = tasks.removeValue(forKey: id) {
            t.cancel()
            Diagnostics.video("[Bootstrap] cancel id=\(id)")
        }
    }
}