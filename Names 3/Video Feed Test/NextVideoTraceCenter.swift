import Foundation
import os
import os.signpost
import QuartzCore
import Photos

enum NextTracePath: String, Sendable {
    case prefetchedItem
    case prefetchedAsset
    case directRequest
    case unknown
}

actor NextVideoTraceCenter {
    static let shared = NextVideoTraceCenter()

    private struct QueueSnapshot {
        let label: String
        let time: CFTimeInterval
        let avAssetInFlight: Int
        let avAssetCached: Int
        let avAssetWaiters: Int
        let itemInFlight: Int
        let itemCached: Int
        let itemWaiters: Int
    }

    private struct Trace {
        let assetID: String
        let idx: Int
        let total: Int
        let t0: CFTimeInterval
        var path: NextTracePath = .unknown

        var prefetchIndices: [Int] = []

        var requestStart: CFTimeInterval?
        var requestEnd: CFTimeInterval?
        var appliedAt: CFTimeInterval?
        var readyAt: CFTimeInterval?
        var firstFrameAt: CFTimeInterval?

        var stallCount: Int = 0
        var stallTotal: Double = 0
        var stallStart: CFTimeInterval?

        var cancelled: Bool = false
        var failed: Bool = false

        var photokitInCloud: Bool?
        var photokitCancelled: Bool?
        var photokitError: String?

        var queues: [QueueSnapshot] = []

        var signpostID: OSSignpostID?
    }

    private var active: Trace?

    private func now() -> CFTimeInterval { CACurrentMediaTime() }

    func begin(assetID: String, idx: Int, total: Int) async {
        await finishIfAny(reason: "new-begin")
        var sp: OSSignpostID?
        Diagnostics.signpostBegin("NextVideoTrace", id: &sp)
        active = Trace(assetID: assetID, idx: idx, total: total, t0: now(), signpostID: sp)
        Diagnostics.log("[NextTrace] begin id=\(assetID) idx=\(idx)/\(total) tag=\(Diagnostics.shortTag(for: assetID))")
        await sampleQueues(label: "begin")
    }

    func markPrefetchWindow(currentIndex: Int, window: [Int]) async {
        guard var t = active else { return }
        t.prefetchIndices = window
        active = t
        Diagnostics.log("[NextTrace] prefetchWindow cur=\(currentIndex) window=\(window)")
        await sampleQueues(label: "prefetchWindow")
    }

    func markPath(_ path: NextTracePath) {
        guard var t = active else { return }
        t.path = path
        active = t
    }

    func markRequestStart() async {
        guard var t = active else { return }
        t.requestStart = now()
        active = t
        await sampleQueues(label: "requestStart")
    }

    func markRequestEnd(info: [AnyHashable: Any]?) async {
        guard var t = active else { return }
        t.requestEnd = now()
        if let info {
            t.photokitInCloud = (info[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue
            t.photokitCancelled = (info[PHImageCancelledKey] as? NSNumber)?.boolValue
            t.photokitError = (info[PHImageErrorKey] as? NSError)?.localizedDescription
        }
        active = t
        await sampleQueues(label: "requestEnd")
    }

    func markApplied() async {
        guard var t = active else { return }
        t.appliedAt = now()
        active = t
        await sampleQueues(label: "applied")
    }

    func markReady() async {
        guard var t = active else { return }
        t.readyAt = now()
        active = t
        await sampleQueues(label: "ready")
    }

    func markFirstFrame() async {
        guard var t = active else { return }
        t.firstFrameAt = now()
        active = t
        await sampleQueues(label: "firstFrame")
        await finishIfAny(reason: "firstFrame")
    }

    func stallBegan() {
        guard var t = active, t.stallStart == nil else { return }
        t.stallStart = now()
        active = t
        Diagnostics.log("[NextTrace] stall begin id=\(t.assetID)")
    }

    func stallEnded() {
        guard var t = active, let s = t.stallStart else { return }
        let dt = now() - s
        t.stallCount += 1
        t.stallTotal += dt
        t.stallStart = nil
        active = t
        Diagnostics.log(String(format: "[NextTrace] stall end id=%@ dt=%.2fs", t.assetID, dt))
    }

    func finish(cancelled: Bool = false, failed: Bool = false) async {
        guard var t = active else { return }
        t.cancelled = cancelled || (t.photokitCancelled ?? false)
        t.failed = failed
        active = t
        await finishIfAny(reason: cancelled ? "cancel" : (failed ? "failed" : "finish"))
    }

    private func sampleQueues(label: String) async {
        guard var t = active else { return }
        async let a = VideoPrefetcher.shared.stats()
        async let b = PlayerItemPrefetcher.shared.stats()
        let (aa, bb) = await (a, b)
        let snap = QueueSnapshot(
            label: label,
            time: now(),
            avAssetInFlight: aa.inFlight, avAssetCached: aa.cached, avAssetWaiters: aa.waiters,
            itemInFlight: bb.inFlight, itemCached: bb.cached, itemWaiters: bb.waiters
        )
        t.queues.append(snap)
        active = t
        Diagnostics.videoPerf("[NextTrace] queues[\(label)] asset(inFlight/cached/waiters)=\(aa.inFlight)/\(aa.cached)/\(aa.waiters) item(inFlight/cached/waiters)=\(bb.inFlight)/\(bb.cached)/\(bb.waiters)")
    }

    private func finishIfAny(reason: String) async {
        guard var t = active else { return }
        Diagnostics.signpostEnd("NextVideoTrace", id: t.signpostID)
        t.signpostID = nil
        active = nil

        func d(_ s: CFTimeInterval?, _ e: CFTimeInterval?) -> Double? {
            guard let s, let e else { return nil }
            return max(0, e - s)
        }
        let reqDur = d(t.requestStart, t.requestEnd)
        let a2r = d(t.appliedAt, t.readyAt)
        let a2f = d(t.appliedAt, t.firstFrameAt)

        let tag = Diagnostics.shortTag(for: t.assetID)
        let wnd = t.prefetchIndices.isEmpty ? "[]" : "[\(t.prefetchIndices.map(String.init).joined(separator: ","))]"
        let qLast = t.queues.last
        let qStr: String = {
            guard let q = qLast else { return "noQ" }
            return "Q a=\(q.avAssetInFlight)/\(q.avAssetCached)/\(q.avAssetWaiters) i=\(q.itemInFlight)/\(q.itemCached)/\(q.itemWaiters)"
        }()

        Diagnostics.videoPerf(String(format: "[NextTrace] end reason=%@ id=%@ tag=%@ idx=%d/%d path=%@ prefetch=%@ req=%.0fms a→r=%.0fms a→f=%.0fms stalls=%d/%.2fs cancelled=%@ failed=%@ %@",
                                     reason, t.assetID, tag, t.idx, t.total, t.path.rawValue,
                                     wnd,
                                     (reqDur ?? -1)*1000, (a2r ?? -1)*1000, (a2f ?? -1)*1000,
                                     t.stallCount, t.stallTotal,
                                     (t.cancelled ? "true" : (t.photokitCancelled.map { "\($0)" } ?? "nil")),
                                     t.failed ? "true" : "false",
                                     qStr))
    }
}