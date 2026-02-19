import Foundation
import Photos
import QuartzCore
import os.signpost

@MainActor
final class FirstLaunchProbe {
    static let shared = FirstLaunchProbe()
    
    private var started = false
    private let t0: CFTimeInterval = CACurrentMediaTime()
    
    private var tAppInit: CFTimeInterval?
    private var tContentAppear: CFTimeInterval?
    private var tFeedAppear: CFTimeInterval?
    
    private var authInitial: PHAuthorizationStatus?
    private var tAuthRequested: CFTimeInterval?
    private var tAuthResult: CFTimeInterval?
    private var authResult: PHAuthorizationStatus?
    
    private var tStartWindowBegin: CFTimeInterval?
    private var tWindowPublished: CFTimeInterval?
    
    private(set) var firstAssetID: String?
    private var tFirstCellMounted: CFTimeInterval?
    
    private var tPrefetchStarted: CFTimeInterval?
    private var tPrefetchCached: CFTimeInterval?
    
    private var tPlayerSetAsset: CFTimeInterval?
    private var tPlayerUsedPrefetch: CFTimeInterval?
    private var tPlayerRequestBegin: CFTimeInterval?
    private var tPlayerRequestInfo: CFTimeInterval?
    private var requestInCloud = false
    private var requestCancelled = false
    private var requestErrorDesc: String?
    private var requestProgressMax: Double = 0
    
    private var tPlayerItemReady: CFTimeInterval?
    private var likelyToKeepUp: Bool?
    
    private var tFirstFrame: CFTimeInterval?
    private var didSummarize = false
    
    private var tPrefetchCall: CFTimeInterval?
    private var tPrefetchEnqueue: CFTimeInterval?
    private var tPrefetchActorEnter: CFTimeInterval?
    private var tPrefetchRequestCall: CFTimeInterval?
    
    private var tPlayerApplyItem: CFTimeInterval?
    private var tPlayerItemUnknownFirst: CFTimeInterval?
    private var tPlayerAssetKeysLoaded: CFTimeInterval?

    // Main drift monitor
    private var driftTimer: DispatchSourceTimer?
    private var driftLast: CFTimeInterval?
    private var driftPeak: Double = 0
    private var driftSamples: Int = 0
    private var driftEvents: [(time: CFTimeInterval, drift: Double)] = []

    // Service spans
    private var svcPrepareBegin: [String: CFTimeInterval] = [:]
    private var svcPrepareEnd: [String: CFTimeInterval] = [:]
    private var svcStartBegin: [String: CFTimeInterval] = [:]
    private var svcStartEnd: [String: CFTimeInterval] = [:]

    // Signpost IDs to visualize critical windows in Instruments
    private var spPrefetchEnqueueActor: OSSignpostID?
    private var spPrefetchActorRequest: OSSignpostID?
    private var spPrefetchRequestStart: OSSignpostID?
    private var spApplyItemReady: OSSignpostID?

    private var marks: [(time: CFTimeInterval, label: String)] = []

    private func rel(_ t: CFTimeInterval?) -> String {
        guard let t else { return "nil" }
        return String(format: "%.3fs", t - t0)
    }
    
    private func dt(_ a: CFTimeInterval?, _ b: CFTimeInterval?) -> String {
        guard let a, let b else { return "n/a" }
        return String(format: "%.3fs", b - a)
    }
    
    func appInit() {
        guard !started else { return }
        started = true
        tAppInit = CACurrentMediaTime()
        Diagnostics.log("BootProbe appInit t=\(rel(tAppInit))")
    }
    
    func contentAppear() {
        tContentAppear = CACurrentMediaTime()
        Diagnostics.log("BootProbe contentAppear t=\(rel(tContentAppear))")
    }
    
    func feedAppear() {
        tFeedAppear = CACurrentMediaTime()
        Diagnostics.log("BootProbe feedAppear t=\(rel(tFeedAppear))")
    }
    
    func recordAuthInitial(_ status: PHAuthorizationStatus) {
        authInitial = status
        Diagnostics.log("BootProbe authInitial=\(String(describing: status.rawValue))")
    }
    
    func recordAuthRequested() {
        tAuthRequested = CACurrentMediaTime()
        Diagnostics.log("BootProbe authRequested t=\(rel(tAuthRequested))")
    }
    
    func recordAuthResult(_ status: PHAuthorizationStatus) {
        authResult = status
        tAuthResult = CACurrentMediaTime()
        Diagnostics.log("BootProbe authResult=\(String(describing: status.rawValue)) dt(request->result)=\(dt(tAuthRequested, tAuthResult))")
    }
    
    func startWindowBegin() {
        tStartWindowBegin = CACurrentMediaTime()
        Diagnostics.log("BootProbe startWindowBegin t=\(rel(tStartWindowBegin))")
    }
    
    func windowPublished(items: Int, firstID: String) {
        tWindowPublished = CACurrentMediaTime()
        if firstAssetID == nil {
            firstAssetID = firstID
        }
        Diagnostics.log("BootProbe windowPublished items=\(items) firstID=\(firstID) t=\(rel(tWindowPublished)) dt(start->publish)=\(dt(tStartWindowBegin, tWindowPublished))")
    }
    
    func firstCellMounted() {
        guard tFirstCellMounted == nil else { return }
        tFirstCellMounted = CACurrentMediaTime()
        Diagnostics.log("BootProbe firstCellMounted t=\(rel(tFirstCellMounted))")
    }
    
    func prefetchCall(id: String) {
        guard id == firstAssetID || firstAssetID == nil else { return }
        if firstAssetID == nil { firstAssetID = id }
        guard tPrefetchCall == nil else { return }
        tPrefetchCall = CACurrentMediaTime()
        Diagnostics.log("BootProbe prefetchCall id=\(id) t=\(rel(tPrefetchCall))")
        // BEGIN: PrefetchEnqueue→Actor span
        Diagnostics.signpostBegin("PrefetchEnqueueToActor", id: &spPrefetchEnqueueActor)
    }

    func prefetchEnqueue(id: String) {
        guard id == firstAssetID else { return }
        guard tPrefetchEnqueue == nil else { return }
        tPrefetchEnqueue = CACurrentMediaTime()
        Diagnostics.log("BootProbe prefetchEnqueue id=\(id) t=\(rel(tPrefetchEnqueue))")
    }

    func prefetchActorEnter(id: String) {
        guard id == firstAssetID else { return }
        guard tPrefetchActorEnter == nil else { return }
        tPrefetchActorEnter = CACurrentMediaTime()
        Diagnostics.log("BootProbe prefetchActorEnter id=\(id) t=\(rel(tPrefetchActorEnter))")
        // END previous, BEGIN Actor→RequestCall span
        Diagnostics.signpostEnd("PrefetchEnqueueToActor", id: spPrefetchEnqueueActor)
        Diagnostics.signpostBegin("PrefetchActorToRequestCall", id: &spPrefetchActorRequest)
    }
    
    func prefetchRequestCall(id: String) {
        guard id == firstAssetID else { return }
        guard tPrefetchRequestCall == nil else { return }
        tPrefetchRequestCall = CACurrentMediaTime()
        Diagnostics.log("BootProbe prefetchRequestCall id=\(id) t=\(rel(tPrefetchRequestCall))")
        // END previous, BEGIN RequestCall→Start span
        Diagnostics.signpostEnd("PrefetchActorToRequestCall", id: spPrefetchActorRequest)
        Diagnostics.signpostBegin("PrefetchRequestCallToStart", id: &spPrefetchRequestStart)
    }

    func prefetchStarted(id: String) {
        guard id == firstAssetID else { return }
        guard tPrefetchStarted == nil else { return }
        tPrefetchStarted = CACurrentMediaTime()
        Diagnostics.log("BootProbe prefetchStarted id=\(id) t=\(rel(tPrefetchStarted))")
        // END RequestCall→Start span
        Diagnostics.signpostEnd("PrefetchRequestCallToStart", id: spPrefetchRequestStart)
    }
    
    func prefetchCached(id: String) {
        guard id == firstAssetID else { return }
        guard tPrefetchCached == nil else { return }
        tPrefetchCached = CACurrentMediaTime()
        Diagnostics.log("BootProbe prefetchCached id=\(id) t=\(rel(tPrefetchCached)) dt(start->cache)=\(dt(tPrefetchStarted, tPrefetchCached))")
    }
    
    func playerSetAsset(id: String) {
        guard id == firstAssetID || firstAssetID == nil else { return }
        if firstAssetID == nil { firstAssetID = id }
        tPlayerSetAsset = CACurrentMediaTime()
        Diagnostics.log("BootProbe playerSetAsset id=\(id) t=\(rel(tPlayerSetAsset))")
    }
    
    func playerUsedPrefetch(id: String) {
        guard id == firstAssetID else { return }
        guard tPlayerUsedPrefetch == nil else { return }
        tPlayerUsedPrefetch = CACurrentMediaTime()
        Diagnostics.log("BootProbe playerUsedPrefetch id=\(id) t=\(rel(tPlayerUsedPrefetch))")
    }
    
    func playerRequestBegin(id: String) {
        guard id == firstAssetID else { return }
        guard tPlayerRequestBegin == nil else { return }
        tPlayerRequestBegin = CACurrentMediaTime()
        Diagnostics.log("BootProbe playerRequestBegin id=\(id) t=\(rel(tPlayerRequestBegin))")
    }
    
    func playerRequestProgress(id: String, progress: Double) {
        guard id == firstAssetID else { return }
        if progress > requestProgressMax { requestProgressMax = progress }
    }
    
    func playerRequestInfo(id: String, inCloud: Bool, cancelled: Bool, errorDesc: String?) {
        guard id == firstAssetID else { return }
        requestInCloud = inCloud
        requestCancelled = cancelled
        requestErrorDesc = errorDesc
        tPlayerRequestInfo = CACurrentMediaTime()
        Diagnostics.log(#"BootProbe playerRequestInfo id=\#(id) inCloud=\#(inCloud) cancelled=\#(cancelled) error=\#(String(describing: errorDesc)) t=\#(rel(tPlayerRequestInfo)) dt(reqStart->info)=\#(dt(tPlayerRequestBegin, tPlayerRequestInfo)) progressMax=\#(String(format: "%.0f%%", requestProgressMax * 100))"#)
    }
    
    func playerItemReady(id: String) {
        guard id == firstAssetID else { return }
        guard tPlayerItemReady == nil else { return }
        tPlayerItemReady = CACurrentMediaTime()
        Diagnostics.log("BootProbe playerItemReady id=\(id) t=\(rel(tPlayerItemReady))")
        // END: ApplyItem→Ready span
        Diagnostics.signpostEnd("ApplyItemToReady", id: spApplyItemReady)
    }
    
    func playerLikelyToKeepUp(_ value: Bool) {
        likelyToKeepUp = value
    }
    
    func playerApplyItem(id: String) {
        guard id == firstAssetID else { return }
        guard tPlayerApplyItem == nil else { return }
        tPlayerApplyItem = CACurrentMediaTime()
        Diagnostics.log("BootProbe playerApplyItem id=\(id) t=\(rel(tPlayerApplyItem))")
        // BEGIN: ApplyItem→Ready span
        Diagnostics.signpostBegin("ApplyItemToReady", id: &spApplyItemReady)
    }
    
    func playerItemStatusUnknownFirst(id: String) {
        guard id == firstAssetID else { return }
        guard tPlayerItemUnknownFirst == nil else { return }
        tPlayerItemUnknownFirst = CACurrentMediaTime()
        Diagnostics.log("BootProbe playerItemStatusUnknownFirst id=\(id) t=\(rel(tPlayerItemUnknownFirst))")
    }
    
    func playerAssetKeysLoaded(id: String) {
        guard id == firstAssetID else { return }
        guard tPlayerAssetKeysLoaded == nil else { return }
        tPlayerAssetKeysLoaded = CACurrentMediaTime()
        Diagnostics.log("BootProbe playerAssetKeysLoaded id=\(id) t=\(rel(tPlayerAssetKeysLoaded))")
    }

    func mark(_ label: String) {
        let now = CACurrentMediaTime()
        marks.append((time: now, label: label))
        Diagnostics.log("BootProbe mark \(label) t=\(rel(now))")
    }

    // Main drift monitor
    func startMainDriftMonitor() {
        guard driftTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let interval: TimeInterval = 0.5
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if let last = self.driftLast {
                let drift = now - last - interval
                self.driftSamples += 1
                if drift > self.driftPeak { self.driftPeak = drift }
                if drift > 0.200 {
                    self.driftEvents.append((time: now, drift: drift))
                    Diagnostics.log(#"BootProbe MainDrift drift=\#(String(format: "%.3f", drift))s t=\#(String(format: "%.3f", now - self.t0))s samples=\#(self.driftSamples)"#)
                }
            }
            self.driftLast = now
        }
        driftTimer = timer
        driftLast = CACurrentMediaTime()
        Diagnostics.log("BootProbe MainDrift start")
        timer.resume()
    }
    
    func stopMainDriftMonitor() {
        driftTimer?.cancel()
        driftTimer = nil
        Diagnostics.log(#"BootProbe MainDrift stop peak=\#(String(format: "%.3f", driftPeak))s samples=\#(driftSamples)"#)
    }

    // Service spans (prepare/start)
    func servicePrepareBegin(key: String, onMain: Bool) {
        let t = CACurrentMediaTime()
        svcPrepareBegin[key] = t
        Diagnostics.log("BootProbe svc.prepare.begin key=\(key) t=\(rel(t)) onMain=\(onMain)")
    }

    func servicePrepareEnd(key: String, onMain: Bool) {
        let t = CACurrentMediaTime()
        svcPrepareEnd[key] = t
        Diagnostics.log("BootProbe svc.prepare.end key=\(key) t=\(rel(t)) onMain=\(onMain)")
    }

    func serviceStartBegin(key: String, onMain: Bool) {
        let t = CACurrentMediaTime()
        svcStartBegin[key] = t
        Diagnostics.log("BootProbe svc.start.begin key=\(key) t=\(rel(t)) onMain=\(onMain)")
    }

    func serviceStartEnd(key: String, onMain: Bool) {
        let t = CACurrentMediaTime()
        svcStartEnd[key] = t
        Diagnostics.log("BootProbe svc.start.end key=\(key) t=\(rel(t)) onMain=\(onMain)")
    }

    private func overlap(_ aStart: CFTimeInterval?, _ aEnd: CFTimeInterval?, _ bStart: CFTimeInterval?, _ bEnd: CFTimeInterval?) -> CFTimeInterval {
        guard let a0 = aStart, let a1 = aEnd, let b0 = bStart, let b1 = bEnd else { return 0 }
        let s = max(a0, b0)
        let e = min(a1, b1)
        return max(0, e - s)
    }

    private func summarizeOverlaps() {
        let w1 = (tPrefetchEnqueue, tPrefetchActorEnter)
        let w2 = (tPrefetchActorEnter, tPrefetchRequestCall)
        let w3 = (tPrefetchRequestCall, tPrefetchStarted)
        let w4 = (tPlayerApplyItem, tPlayerItemReady)

        func fmt(_ name: String, _ w: (CFTimeInterval?, CFTimeInterval?)) -> String {
            let dtStr = dt(w.0, w.1)
            return "\(name)[\(dtStr)]"
        }

        Diagnostics.log("BootProbe Overlap windows: \(fmt("enqueue→actor", w1)), \(fmt("actor→request", w2)), \(fmt("request→start", w3)), \(fmt("applyItem→ready", w4))")

        for (key, sBegin) in svcStartBegin {
            let sEnd = svcStartEnd[key]
            let o1 = overlap(w1.0, w1.1, sBegin, sEnd)
            let o2 = overlap(w2.0, w2.1, sBegin, sEnd)
            let o3 = overlap(w3.0, w3.1, sBegin, sEnd)
            let o4 = overlap(w4.0, w4.1, sBegin, sEnd)
            let total = (o1 + o2 + o3 + o4)
            if total > 0 {
                Diagnostics.log(String(format: "BootProbe Overlap: service=%@ overlaps e→a=%.3fs a→r=%.3fs r→s=%.3fs apply→ready=%.3fs total=%.3fs begin=%@ end=%@",
                                       key, o1, o2, o3, o4, total, rel(sBegin), rel(sEnd)))
            }
        }

        if !driftEvents.isEmpty {
            Diagnostics.log("BootProbe MainDrift events count=\(driftEvents.count)")
            for e in driftEvents.prefix(12) {
                Diagnostics.log(String(format: "BootProbe MainDrift event t=%.3fs drift=%.3fs", e.time - t0, e.drift))
            }
            if driftEvents.count > 12 {
                Diagnostics.log("BootProbe MainDrift events (remaining) count=\(driftEvents.count - 12)")
            }
        }

        if !marks.isEmpty {
            Diagnostics.log("BootProbe Timeline marks count=\(marks.count)")
            for m in marks.prefix(24) {
                Diagnostics.log(String(format: "BootProbe Mark t=%@ label=%@", rel(m.time), m.label))
            }
            if marks.count > 24 {
                Diagnostics.log("BootProbe Timeline marks (remaining) count=\(marks.count - 24)")
            }
        }
    }
    
    private func summarizeIfPossible() {
        guard !didSummarize else { return }
        guard let tFirstFrame else { return }
        didSummarize = true
        
        let svcPrep = svcPrepareBegin.keys.sorted().map { key in
            if let b = svcPrepareBegin[key], let e = svcPrepareEnd[key] {
                return "\(key)=\(String(format: "%.3fs", e - b)) (begin=\(rel(b)) end=\(rel(e)))"
            } else { return "\(key)=n/a" }
        }.joined(separator: ", ")
        let svcStart = svcStartBegin.keys.sorted().map { key in
            if let b = svcStartBegin[key], let e = svcStartEnd[key] {
                return "\(key)=\(String(format: "%.3fs", e - b)) (begin=\(rel(b)) end=\(rel(e)))"
            } else { return "\(key)=n/a" }
        }.joined(separator: ", ")

        let parts: [String] = [
            "RootCause Summary:",
            "total(appInit->firstFrame)=\(dt(tAppInit, tFirstFrame))",
            "contentAppear@\(rel(tContentAppear)) feedAppear@\(rel(tFeedAppear))",
            "auth(initial=\(String(describing: authInitial?.rawValue)) req@\(rel(tAuthRequested)) res=\(String(describing: authResult?.rawValue)) dt=\(dt(tAuthRequested, tAuthResult)))",
            "window(begin@\(rel(tStartWindowBegin)) publish@\(rel(tWindowPublished)) dt=\(dt(tStartWindowBegin, tWindowPublished)))",
            "firstCellMounted@\(rel(tFirstCellMounted))",
            #"prefetch(call@\#(rel(tPrefetchCall)) enqueue@\#(rel(tPrefetchEnqueue)) actorEnter@\#(rel(tPrefetchActorEnter)) requestCall@\#(rel(tPrefetchRequestCall)) start@\#(rel(tPrefetchStarted)) cache@\#(rel(tPrefetchCached)) dt(call->enqueue)=\#(dt(tPrefetchCall, tPrefetchEnqueue)) dt(enqueue->actor)=\#(dt(tPrefetchEnqueue, tPrefetchActorEnter)) dt(actor->request)=\#(dt(tPrefetchActorEnter, tPrefetchRequestCall)) dt(request->start)=\#(dt(tPrefetchRequestCall, tPrefetchStarted)) dt(start->cache)=\#(dt(tPrefetchStarted, tPrefetchCached)))"#,
            #"player(set@\#(rel(tPlayerSetAsset)) applyItem@\#(rel(tPlayerApplyItem)) unknownFirst@\#(rel(tPlayerItemUnknownFirst)) keysLoaded@\#(rel(tPlayerAssetKeysLoaded)) usedPrefetch@\#(rel(tPlayerUsedPrefetch)) reqBegin@\#(rel(tPlayerRequestBegin)) info@\#(rel(tPlayerRequestInfo)) itemReady@\#(rel(tPlayerItemReady)) firstFrame@\#(rel(tFirstFrame)))"#,
            #"player dt(applyItem->ready)=\#(dt(tPlayerApplyItem, tPlayerItemReady)) dt(keysLoaded->ready)=\#(dt(tPlayerAssetKeysLoaded, tPlayerItemReady)) dt(itemReady->firstFrame)=\#(dt(tPlayerItemReady, tFirstFrame))"#,
            #"photokit(inCloud=\#(requestInCloud) cancelled=\#(requestCancelled) error=\#(String(describing: requestErrorDesc)) maxProgress=\#(String(format: "%.0f%%", requestProgressMax * 100)))"#,
            "services.prepare{\(svcPrep)} services.start{\(svcStart)}",
            #"mainDrift(peak=\#(String(format: "%.3f", driftPeak))s samples=\#(driftSamples))"#
        ]
        for line in parts {
            Diagnostics.log("BootProbe \(line)")
        }
        summarizeOverlaps()
    }

    func firstFrameDisplayed(id: String) {
        guard id == firstAssetID else { return }
        guard tFirstFrame == nil else { return }
        tFirstFrame = CACurrentMediaTime()
        Diagnostics.log("BootProbe firstFrameDisplayed id=\(id) t=\(rel(tFirstFrame))")
        stopMainDriftMonitor()
        summarizeIfPossible()
    }
}