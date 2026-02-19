import Foundation
import AVFoundation
import QuartzCore
import os
import os.signpost
import Photos

enum VideoLoadPath: String, Sendable {
    case prefetchedItem
    case prefetchedAsset
    case directRequest
    case unknown
}

struct VideoLoadMetrics: Sendable {
    let assetID: String
    let path: VideoLoadPath

    let requestStartAt: CFTimeInterval?
    let requestEndAt: CFTimeInterval?
    let applyAt: CFTimeInterval?
    let readyAt: CFTimeInterval?
    let firstFrameAt: CFTimeInterval?

    let stallCount: Int
    let stallTotalSeconds: Double

    let photokitInCloud: Bool?
    let photokitCancelled: Bool?
    let photokitError: String?

    let cancelled: Bool
    let failed: Bool
}

actor VideoPerfStore {
    static let shared = VideoPerfStore()
    private var records: [String: [VideoLoadMetrics]] = [:]

    private var recent: [VideoLoadMetrics] = []
    private var lastDigestAt: CFTimeInterval = 0

    func record(_ metrics: VideoLoadMetrics) {
        var arr = records[metrics.assetID] ?? []
        arr.append(metrics)
        records[metrics.assetID] = arr

        let reqDur = duration(s: metrics.requestStartAt, e: metrics.requestEndAt)
        let applyToReady = duration(s: metrics.applyAt, e: metrics.readyAt)
        let applyToFirst = duration(s: metrics.applyAt, e: metrics.firstFrameAt)
        let tag = Diagnostics.shortTag(for: metrics.assetID)
        let line = String(format: "[VideoPerf] id=%@ path=%@ req=%.3fs apply→ready=%.3fs apply→first=%.3fs stalls=%d/%.2fs inCloud=%@ cancelled=%@ failed=%@",
                          metrics.assetID,
                          metrics.path.rawValue,
                          reqDur ?? -1,
                          applyToReady ?? -1,
                          applyToFirst ?? -1,
                          metrics.stallCount,
                          metrics.stallTotalSeconds,
                          (metrics.photokitInCloud.map { "\($0)" } ?? "nil"),
                          (metrics.cancelled ? "true" : (metrics.photokitCancelled.map { "\($0)" } ?? "nil")),
                          metrics.failed ? "true" : "false") + " tag=\(tag)"
        Diagnostics.videoPerf(line)

        recent.append(metrics)
        if recent.count > 120 { recent.removeFirst(recent.count - 120) }
        maybeEmitDigest()
    }

    private func duration(s: CFTimeInterval?, e: CFTimeInterval?) -> Double? {
        guard let s, let e else { return nil }
        return max(0, e - s)
    }

    private func maybeEmitDigest() {
        let now = CACurrentMediaTime()
        let should = recent.count % 10 == 0 || (now - lastDigestAt) > 5
        guard should, !recent.isEmpty else { return }
        lastDigestAt = now

        func durations(_ pick: (VideoLoadMetrics) -> Double?) -> [Double] {
            recent.compactMap(pick)
        }
        func p(_ values: [Double], _ q: Double) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            let idx = min(max(Int(Double(sorted.count - 1) * q), 0), sorted.count - 1)
            return sorted[idx]
        }
        let req = durations { m in
            guard let s = m.requestStartAt, let e = m.requestEndAt else { return nil }
            return e - s
        }
        let a2r = durations { m in
            guard let s = m.applyAt, let e = m.readyAt else { return nil }
            return e - s
        }
        let a2f = durations { m in
            guard let s = m.applyAt, let e = m.firstFrameAt else { return nil }
            return e - s
        }

        let p50Req = p(req, 0.50) ?? -1
        let p95Req = p(req, 0.95) ?? -1
        let p50A2R = p(a2r, 0.50) ?? -1
        let p95A2R = p(a2r, 0.95) ?? -1
        let p50A2F = p(a2f, 0.50) ?? -1
        let p95A2F = p(a2f, 0.95) ?? -1

        let n = Double(recent.count)
        let byPath = Dictionary(grouping: recent, by: { $0.path })
        let hitPrefItem = Double(byPath[.prefetchedItem]?.count ?? 0) / n
        let hitPrefAsset = Double(byPath[.prefetchedAsset]?.count ?? 0) / n
        let direct = Double(byPath[.directRequest]?.count ?? 0) / n

        let stalls = recent.map { $0.stallCount }
        let stallRate = Double(stalls.filter { $0 > 0 }.count) / n
        let stallTotal = recent.map { $0.stallTotalSeconds }.reduce(0, +)

        let cancelledRate = Double(recent.filter { $0.cancelled }.count) / n

        Diagnostics.videoPerf(String(format: "[VideoPerfDigest] n=%d req(p50/p95)=%.0f/%.0f ms a→r=%.0f/%.0f ms a→f=%.0f/%.0f ms hit(prefItem/prefAsset/direct)=%.0f/%.0f/%.0f%% stalls(rate/total)=%.0f%%/%.2fs cancelled=%.0f%%",
                                     Int(n),
                                     p50Req*1000, p95Req*1000,
                                     p50A2R*1000, p95A2R*1000,
                                     p50A2F*1000, p95A2F*1000,
                                     hitPrefItem*100, hitPrefAsset*100, direct*100,
                                     stallRate*100, stallTotal,
                                     cancelledRate*100))
    }
}

@MainActor
final class VideoLoadProbe {
    private let assetID: String
    private var path: VideoLoadPath = .unknown

    private var requestStartAt: CFTimeInterval?
    private var requestEndAt: CFTimeInterval?
    private var applyAt: CFTimeInterval?
    private var readyAt: CFTimeInterval?
    private var firstFrameAt: CFTimeInterval?

    private var stallStart: CFTimeInterval?
    private var stallCount: Int = 0
    private var stallTotal: Double = 0

    private var inCloud: Bool?
    private var cancelled: Bool?
    private var error: String?

    private var didFinish = false

    private var spRequestID: OSSignpostID?
    private var spApplyToFirstFrame: OSSignpostID?

    init(assetID: String) {
        self.assetID = assetID
    }

    func markPath(_ path: VideoLoadPath) {
        self.path = path
    }

    func markRequestStart() {
        requestStartAt = CACurrentMediaTime()
        Diagnostics.signpostBegin("PlayerItemRequestToReturn", id: &spRequestID)
        Diagnostics.videoPerf("[VideoProbe] id=\(assetID) request start")
    }

    func markRequestEnd(info: [AnyHashable: Any]?) {
        requestEndAt = CACurrentMediaTime()
        Diagnostics.signpostEnd("PlayerItemRequestToReturn", id: spRequestID)
        spRequestID = nil
        if let info {
            inCloud = (info[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue
            cancelled = (info[PHImageCancelledKey] as? NSNumber)?.boolValue
            error = (info[PHImageErrorKey] as? NSError)?.localizedDescription
        }
        Diagnostics.videoPerf("[VideoProbe] id=\(assetID) request end inCloud=\(inCloud.map { "\($0)" } ?? "nil") cancelled=\(cancelled.map { "\($0)" } ?? "nil") error=\(String(describing: error))")
    }

    func markApplied() {
        applyAt = CACurrentMediaTime()
        Diagnostics.signpostBegin("ApplyItemToFirstFrame", id: &spApplyToFirstFrame)
        Diagnostics.videoPerf("[VideoProbe] id=\(assetID) applied item")
    }

    func markReady() {
        readyAt = CACurrentMediaTime()
        Diagnostics.videoPerf("[VideoProbe] id=\(assetID) readyToPlay")
    }

    func markFirstFrame() {
        firstFrameAt = CACurrentMediaTime()
        Diagnostics.signpostEnd("ApplyItemToFirstFrame", id: spApplyToFirstFrame)
        spApplyToFirstFrame = nil
        Diagnostics.videoPerf("[VideoProbe] id=\(assetID) firstFrame")
    }

    func stallBegan() {
        guard stallStart == nil else { return }
        stallStart = CACurrentMediaTime()
        Diagnostics.videoPerf("[VideoProbe] id=\(assetID) stall begin")
    }

    func stallEnded() {
        guard let s = stallStart else { return }
        let dt = CACurrentMediaTime() - s
        stallCount += 1
        stallTotal += dt
        stallStart = nil
        Diagnostics.videoPerf(String(format: "[VideoProbe] id=%@ stall end dt=%.2fs", assetID, dt))
    }

    func finish(cancelled: Bool = false, failed: Bool = false) {
        guard !didFinish else { return }
        didFinish = true
        if stallStart != nil {
            stallEnded()
        }
        let metrics = VideoLoadMetrics(
            assetID: assetID,
            path: path,
            requestStartAt: requestStartAt,
            requestEndAt: requestEndAt,
            applyAt: applyAt,
            readyAt: readyAt,
            firstFrameAt: firstFrameAt,
            stallCount: stallCount,
            stallTotalSeconds: stallTotal,
            photokitInCloud: inCloud,
            photokitCancelled: self.cancelled ?? cancelled,
            photokitError: error,
            cancelled: cancelled || (self.cancelled ?? false),
            failed: failed
        )
        Task {
            await VideoPerfStore.shared.record(metrics)
        }
    }
}