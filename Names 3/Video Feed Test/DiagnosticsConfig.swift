import Foundation
import QuartzCore

enum LogVerbosity: String {
    case off, errorsOnly, compact, normal, verbose
}

struct DiagnosticsConfig {
    static var shared = DiagnosticsConfig()

    var verbosity: LogVerbosity
    var throttle: [String: TimeInterval] = [
        "PagedCollection.viewDidLayoutSubviews": 0.5,
        "PagedCollection.interacting": 1.0,
        "Prefetch.queueDepth": 0.5,
        "Prefetch.actor": 0.2,
        "PlayerItemPrefetcher.actor": 0.2,
        "PlayerItemPrefetcher.result": 1.0,
        "Prefetcher.result": 0.8,
        "TikTokCell.loadedTimeRanges": 2.0,
        "TikTokCell.timeControlStatus": 0.5,
        "TikTokCell.rate": 0.5,
        "TikTokCell.likelyToKeepUp": 0.5,
        "TikTokCell.timeJumped": 0.2,
        "TikTokCell.itemStatus": 0.5,
        "TikTokCell.assetLine": 0.5,
        "TikTokPlayerView.firstFrame": 0.5,
        "Perf.WARNING": 5.0,
        "FIGSANDBOX": 2.0,
        "PlayerRemoteXPC": 2.0,
        "AssetTrack.syncAccess": 5.0
    ]

    private static func defaultVerbosity() -> LogVerbosity {
        #if DEBUG
        let fallback: LogVerbosity = .compact
        #else
        let fallback: LogVerbosity = .errorsOnly
        #endif
        if let raw = ProcessInfo.processInfo.environment["VF_LOG"],
           let v = LogVerbosity(rawValue: raw.lowercased()) {
            return v
        }
        return fallback
    }

    init(verbosity: LogVerbosity = DiagnosticsConfig.defaultVerbosity()) {
        self.verbosity = verbosity
    }
}

private final class DiagnosticsFilter {
    static let shared = DiagnosticsFilter()

    private var lastLogAt: [String: CFTimeInterval] = [:]
    private let lock = NSLock()

    private let highSignalKeywords: [String] = [
        "WARNING", "Failed", "error=", "errorLog", "FailedToPlayToEnd", "stall", "[VideoPerfDigest]"
    ]

    private let noisyContains: [String] = [
        "viewDidLayoutSubviews",
        "PagedCollection ",
        "Page mount", "Page unmount",
        "updateUIViewController", "applyUpdates", "refresh cell idx", "current index=",
        "prefetch add", "prefetch cancel",
        "Prefetcher(actor) enter dt", "Prefetcher(actor) started", "Prefetcher facade call",
        "Prefetcher(actor) enqueue", "Prefetcher(actor) already cached",
        "Prefetch(PlayerItem) queueDepth", "Prefetch(AVAsset) queueDepth",
        "PlayerItemPrefetcher(actor)",
        "PlayerItemPrefetcher result",
        "Prefetcher result id=",
        "ReadyIDs +",
        "timeControlStatus=", " rate=", " loadedTimeRanges=",
        "isPlaybackLikelyToKeepUp=", " timeJumped",
        "PlayerLayerView", "PlayerLayer isReadyForDisplay",
        "LeakDetector:", "FeedProbe t=",
        "MixedFeed preheat", "MixedFeed prefetch",
        "TikTokCell] applyItem", "TikTokCell configure:", "TikTokCell cancel",
        "HDR playback flags:",
        "FIGSANDBOX", "PlayerRemoteXPC",
        "Failed to send CA Event for app launch measurements"
    ]

    func shouldEmit(_ message: String, verbosity: LogVerbosity) -> Bool {
        switch verbosity {
        case .off:
            return false
        case .errorsOnly:
            return containsHighSignal(message)
        case .compact:
            if containsHighSignal(message) { return true }
            if message.contains("[VideoPerf]") {
                return compactAllowsVideoPerf(message)
            }
            if message.contains("[VideoProbe] firstFrame") || message.contains("first frame displayed") {
                return true
            }
            for n in noisyContains {
                if message.contains(n) { return false }
            }
            return false
        case .normal:
            return true
        case .verbose:
            return true
        }
    }

    func shouldThrottle(_ message: String, now: CFTimeInterval, verbosity: LogVerbosity) -> Bool {
        guard verbosity != .verbose else { return false }
        if let k = throttleKey(for: message),
           let interval = DiagnosticsConfig.shared.throttle[k],
           interval > 0 {
            lock.lock()
            defer { lock.unlock() }
            let last = lastLogAt[k] ?? 0
            if (now - last) < interval { return true }
            lastLogAt[k] = now
        }
        return false
    }

    private func throttleKey(for message: String) -> String? {
        if message.contains("viewDidLayoutSubviews") { return "PagedCollection.viewDidLayoutSubviews" }
        if message.contains("PagedCollection interacting=") { return "PagedCollection.interacting" }
        if message.contains("Prefetch(PlayerItem) queueDepth") { return "Prefetch.queueDepth" }
        if message.contains("Prefetch(AVAsset) queueDepth") { return "Prefetch.queueDepth" }
        if message.contains("Prefetcher(actor)") { return "Prefetch.actor" }
        if message.contains("PlayerItemPrefetcher(actor)") { return "PlayerItemPrefetcher.actor" }
        if message.contains("PlayerItemPrefetcher result") { return "PlayerItemPrefetcher.result" }
        if message.contains("Prefetcher result id=") { return "Prefetcher.result" }
        if message.contains(" loadedTimeRanges=") { return "TikTokCell.loadedTimeRanges" }
        if message.contains(" timeControlStatus=") { return "TikTokCell.timeControlStatus" }
        if message.contains(" rate=") { return "TikTokCell.rate" }
        if message.contains(" isPlaybackLikelyToKeepUp=") { return "TikTokCell.likelyToKeepUp" }
        if message.contains(" timeJumped") { return "TikTokCell.timeJumped" }
        if message.contains(" item.status=") { return "TikTokCell.itemStatus" }
        if message.contains(" TikTokCell] asset=") { return "TikTokCell.assetLine" }
        if message.contains("first frame displayed") { return "TikTokPlayerView.firstFrame" }
        if message.contains("Perf WARNING: thermal=") { return "Perf.WARNING" }
        if message.contains("FIGSANDBOX") { return "FIGSANDBOX" }
        if message.contains("PlayerRemoteXPC") { return "PlayerRemoteXPC" }
        if message.contains("Asset track property") && message.contains("synchronously before being loaded") { return "AssetTrack.syncAccess" }
        return nil
    }

    private func containsHighSignal(_ message: String) -> Bool {
        for k in highSignalKeywords {
            if message.contains(k) { return true }
        }
        return false
    }

    private func compactAllowsVideoPerf(_ message: String) -> Bool {
        if message.contains("[VideoPerfDigest]") { return true }
        if message.lowercased().contains("stall") { return true }
        if message.contains("failed=true") { return true }
        if message.contains("cancelled=true") { return true }
        return false
    }
}

extension Diagnostics {
    static func shouldEmit(_ message: String) -> Bool {
        let cfg = DiagnosticsConfig.shared
        let now = CACurrentMediaTime()
        if DiagnosticsFilter.shared.shouldThrottle(message, now: now, verbosity: cfg.verbosity) {
            return false
        }
        return DiagnosticsFilter.shared.shouldEmit(message, verbosity: cfg.verbosity)
    }
}