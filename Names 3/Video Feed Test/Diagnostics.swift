//
//  Diagnostics.swift
//  Video Feed Test
//
//  Created by Alex (AI) on 10/1/25.
//

import Foundation
import AVFoundation
import os
import os.signpost
import Photos
import QuartzCore

enum Diagnostics {
    static let logger = Logger(subsystem: "VideoFeedTest", category: "Diagnostics")
    static let signpostLog = OSLog(subsystem: "VideoFeedTest", category: "Signpost")

    static let videoLogger = Logger(subsystem: "VideoFeedTest", category: "Video")
    static let videoPerfLogger = Logger(subsystem: "VideoFeedTest", category: "VideoPerf")

    static func shortTag(for id: String) -> String {
        guard !id.isEmpty else { return "nil" }
        let base = id.split(separator: "/").first.map(String.init) ?? id
        let hex = (base as NSString).replacingOccurrences(of: "[^A-Fa-f0-9]", with: "", options: .regularExpression, range: NSRange(location: 0, length: base.utf16.count))
        if !hex.isEmpty {
            let up = hex.uppercased()
            return up.count >= 3 ? String(up.suffix(3)) : up
        }
        let alnum = (base as NSString).replacingOccurrences(of: "[^A-Za-z0-9]", with: "", options: .regularExpression, range: NSRange(location: 0, length: base.utf16.count)).uppercased()
        return alnum.count >= 3 ? String(alnum.suffix(3)) : (alnum.isEmpty ? "nil" : alnum)
    }

    @discardableResult
    static func signpostBegin(_ name: StaticString, id: inout OSSignpostID?) -> OSSignpostID {
        let sid = id ?? OSSignpostID(log: signpostLog)
        os_signpost(.begin, log: signpostLog, name: name, signpostID: sid)
        id = sid
        return sid
    }

    static func signpostEnd(_ name: StaticString, id: OSSignpostID?) {
        guard let sid = id else { return }
        os_signpost(.end, log: signpostLog, name: name, signpostID: sid)
    }

    // #region agent log
    private static let debugLogPath = "/Users/ricardolopeznovelo/Documents/XCode Projects/Names-3/.cursor/debug-cf9e96.log"
    static func debugBridge(hypothesisId: String, location: String, message: String, data: [String: Any] = [:]) {
        let payload: [String: Any] = [
            "sessionId": "cf9e96",
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: json, encoding: .utf8) else { return }
        let url = URL(fileURLWithPath: debugLogPath)
        if FileManager.default.fileExists(atPath: url.path) {
            if let h = try? FileHandle(forUpdating: url) {
                h.seekToEndOfFile()
                h.write((line + "\n").data(using: .utf8)!)
                try? h.close()
            }
        } else {
            try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        let dataStr = data.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("[Bridge] hyp=\(hypothesisId) \(message) \(dataStr)")
    }
    // #endregion

    static func log(_ message: String) {
        guard shouldEmit(message) else { return }
        switch DiagnosticsConfig.shared.verbosity {
        case .off:
            return
        case .errorsOnly, .compact:
            logger.info("\(message, privacy: .public)")
        case .normal:
            logger.debug("\(message, privacy: .public)")
        case .verbose:
            logger.debug("\(message, privacy: .public)")
        }
    }

    static func video(_ message: String) {
        guard shouldEmit(message) else { return }
        switch DiagnosticsConfig.shared.verbosity {
        case .off:
            return
        case .errorsOnly, .compact:
            videoLogger.info("\(message, privacy: .public)")
        case .normal, .verbose:
            videoLogger.debug("\(message, privacy: .public)")
        }
    }

    static func videoPerf(_ message: String) {
        // Gate per verbosity; keep digest/stalls/errors even in compact, drop generic per-item spam.
        let cfg = DiagnosticsConfig.shared.verbosity
        let lower = message.lowercased()
        let mustKeep = message.contains("[VideoPerfDigest]") || lower.contains("stall") || lower.contains("failed=true") || lower.contains("error")
        if cfg == .off || (cfg == .errorsOnly && !mustKeep) {
            return
        }
        guard shouldEmit(message) || mustKeep else { return }
        videoPerfLogger.info("\(message, privacy: .public)")
    }
}

@MainActor
final class PlayerLeakDetector {
    static let shared = PlayerLeakDetector()

    private let probes = NSHashTable<PlayerProbe>.weakObjects()

    func register(_ probe: PlayerProbe) {
        probes.add(probe)
    }

    func unregister(_ probe: PlayerProbe) {
        probes.remove(probe)
    }

    @discardableResult
    func snapshotActive(log: Bool) -> [(context: String, assetID: String, status: AVPlayer.TimeControlStatus, time: CMTime)] {
        let list: [(context: String, assetID: String, status: AVPlayer.TimeControlStatus, time: CMTime)] = probes.allObjects.map { probe in
            (context: probe.context, assetID: probe.assetID, status: probe.player.timeControlStatus, time: probe.player.currentTime())
        }
        if log {
            if list.isEmpty {
                Diagnostics.log("LeakDetector: No active players")
            } else {
                Diagnostics.log("LeakDetector: Active players count=\(list.count)")
                for e in list {
                    Diagnostics.log("LeakDetector: [\(e.context)] asset=\(e.assetID) status=\(String(describing: e.status)) t=\(CMTimeGetSeconds(e.time))s")
                }
            }
        }
        return list
    }
}

@MainActor
final class PlayerProbe {
    let player: AVPlayer
    let context: String
    let assetID: String

    private var timeControlObs: NSKeyValueObservation?
    private var rateObs: NSKeyValueObservation?
    private var itemStatusObs: NSKeyValueObservation?
    private var itemLikelyObs: NSKeyValueObservation?
    private var itemEmptyObs: NSKeyValueObservation?
    private var itemFullObs: NSKeyValueObservation?
    private var timeObs: Any?
    private var firstFrameLogged = false

    private var phaseID: OSSignpostID?
    private var t0: CFTimeInterval = 0

    init(player: AVPlayer, context: String, assetID: String) {
        self.player = player
        self.context = context
        self.assetID = assetID
        PlayerLeakDetector.shared.register(self)
        attachPlayerObservers()
    }

    deinit {
        // Avoid main-actor calls here to keep Swift 6 happy.
        // Observations use weak self; player timeObserver closure uses weak self.
        // We explicitly nil out probes from owners when tearing down.
    }

    func startPhase(_ name: StaticString) {
        t0 = CACurrentMediaTime()
        Diagnostics.signpostBegin(name, id: &phaseID)
        Diagnostics.log("[\(context)] asset=\(assetID) phase begin: \(name)")
    }

    func endPhase(_ name: StaticString) {
        let dt = CACurrentMediaTime() - t0
        Diagnostics.signpostEnd(name, id: phaseID)
        Diagnostics.log("[\(context)] asset=\(assetID) phase end: \(name) dt=\(String(format: "%.3f", dt))s")
        phaseID = nil
        t0 = 0
    }

    func attach(item: AVPlayerItem) {
        itemStatusObs = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                Diagnostics.log("[\(self.context)] asset=\(self.assetID) item.status=\(String(describing: item.status.rawValue)) error=\(String(describing: item.error?.localizedDescription))")
                if item.status == .readyToPlay {
                    self.logLoadedTimeRanges(item)
                }
            }
        }
        itemLikelyObs = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                Diagnostics.log("[\(self.context)] asset=\(self.assetID) isPlaybackLikelyToKeepUp=\(item.isPlaybackLikelyToKeepUp)")
            }
        }
        itemEmptyObs = item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                Diagnostics.log("[\(self.context)] asset=\(self.assetID) isPlaybackBufferEmpty=\(item.isPlaybackBufferEmpty)")
            }
        }
        itemFullObs = item.observe(\.isPlaybackBufferFull, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                Diagnostics.log("[\(self.context)] asset=\(self.assetID) isPlaybackBufferFull=\(item.isPlaybackBufferFull)")
            }
        }
        installFirstFrameTimeObserver()
    }

    func detach() {
        if let timeObs {
            player.removeTimeObserver(timeObs)
            self.timeObs = nil
        }
        timeControlObs = nil
        rateObs = nil
        itemStatusObs = nil
        itemLikelyObs = nil
        itemEmptyObs = nil
        itemFullObs = nil
        PlayerLeakDetector.shared.unregister(self)
    }

    private func attachPlayerObservers() {
        timeControlObs = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let reason = player.reasonForWaitingToPlay?.rawValue ?? "nil"
                Diagnostics.log("[\(self.context)] asset=\(self.assetID) timeControlStatus=\(String(describing: player.timeControlStatus)) reason=\(reason)")
                if let item = player.currentItem {
                    self.logLoadedTimeRanges(item)
                }
            }
        }
        rateObs = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                Diagnostics.log("[\(self.context)] asset=\(self.assetID) rate=\(player.rate)")
            }
        }
    }

    private func installFirstFrameTimeObserver() {
        firstFrameLogged = false
        timeObs = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.firstFrameLogged, t.seconds > 0 {
                    self.firstFrameLogged = true
                    Diagnostics.log("[\(self.context)] asset=\(self.assetID) firstTimeObserved=\(String(format: "%.3f", t.seconds))s since start=\(String(format: "%.3f", CACurrentMediaTime() - self.t0))s")
                }
            }
        }
    }

    private func logLoadedTimeRanges(_ item: AVPlayerItem) {
        let ranges = item.loadedTimeRanges.compactMap { $0.timeRangeValue }
        let desc = ranges.map { r in
            let start = CMTimeGetSeconds(r.start)
            let dur = CMTimeGetSeconds(r.duration)
            return "[start=\(String(format: "%.2f", start)), dur=\(String(format: "%.2f", dur))]"
        }.joined(separator: ", ")
        Diagnostics.log("[\(context)] asset=\(assetID) loadedTimeRanges=\(desc)")
    }
}

extension PHAsset {
    var diagSummary: String {
        "id=\(localIdentifier) dur=\(String(format: "%.2f", duration))s size=\(pixelWidth)x\(pixelHeight)"
    }
}

struct PhotoKitDiagnostics {
    static func logResultInfo(prefix: String, info: [AnyHashable: Any]?) {
        guard let info else {
            Diagnostics.log("\(prefix) info=nil")
            return
        }
        let inCloud = (info[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue ?? false
        let cancelled = (info[PHImageCancelledKey] as? NSNumber)?.boolValue ?? false
        let error = (info[PHImageErrorKey] as? NSError)
        let keysDesc = Array(info.keys).map { "\($0)" }.joined(separator: ",")
        Diagnostics.log("\(prefix) info: inCloud=\(inCloud) cancelled=\(cancelled) error=\(String(describing: error?.localizedDescription)) keys=\(keysDesc)")
    }
}

extension Notification.Name {
    static let videoPrefetcherDidCacheAsset = Notification.Name("VideoPrefetcherDidCacheAsset")
    static let videoPlaybackItemReady = Notification.Name("VideoPlaybackItemReady")
    static let playerFirstFrameDisplayed = Notification.Name("PlayerFirstFrameDisplayed")

    static let videoPrefetcherDidStart = Notification.Name("videoPrefetcherDidStart")
    static let videoPrefetcherDidFinish = Notification.Name("videoPrefetcherDidFinish")

    static let playerItemPrefetcherDidStart = Notification.Name("playerItemPrefetcherDidStart")
    static let playerItemPrefetcherDidFinish = Notification.Name("playerItemPrefetcherDidFinish")
}