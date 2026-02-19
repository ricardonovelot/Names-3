import Foundation
import UIKit
import MediaPlayer
import os.signpost
import QuartzCore

@MainActor
final class AppleMusicFeatureService: FeatureService {
    let key = "appleMusic"
    private var didPrepare = false
    private var didStart = false

    func prepare() async {
        guard !didPrepare else { return }
        Diagnostics.log("AppleMusicFeature prepare (lightweight)")
        didPrepare = true
    }

    func start() async {
        guard FeatureFlags.enableAppleMusicIntegration else {
            Diagnostics.log("AppleMusicFeature start skipped (flag off)")
            return
        }
        guard !didStart else { return }
        Diagnostics.log("AppleMusicFeature start begin")

        let okFF = await PhaseGate.shared.waitUntil(.firstFrame, timeout: 30)
        let okActive = await PhaseGate.shared.waitUntilAppActive(timeout: 30)
        let finalFF = await PhaseGate.shared.hasReached(.firstFrame)
        let finalActive = await PhaseGate.shared.hasReached(.appActive)
        Diagnostics.log("AppleMusicFeature gates: firstFrame=\(finalFF) appActive=\(finalActive) waitedFF=\(okFF) waitedActive=\(okActive)")
        guard finalFF && finalActive else {
            Diagnostics.log("AppleMusicFeature deferring: gates not satisfied; skipping to avoid early MediaPlayer/Accounts")
            return
        }

        #if DEBUG
        DebugServiceGuards.assertPhaseGate(.mediaPlayer, policy: .onBootAfterFirstFrame)
        #endif

        var sp: OSSignpostID?
        Diagnostics.signpostBegin("AppleMusicFeatureStart", id: &sp)

        let t0 = CACurrentMediaTime()
        Diagnostics.log("AppleMusicFeature prewarm onMain=\(Thread.isMainThread)")
        await MainActor.run {
            AppleMusicController.shared.prewarm()
        }
        let t1 = CACurrentMediaTime()
        Diagnostics.log(#"AppleMusicFeature prewarm done dt=\#(String(format: "%.3f", t1 - t0))s"#)

        // Lazily initialize the monitor now; not at launch.
        _ = MusicPlaybackMonitor.shared
        MusicCenter.shared.attachIfNeeded()

        Diagnostics.signpostEnd("AppleMusicFeatureStart", id: sp)
        Diagnostics.log("AppleMusicFeature start ready")
        didStart = true
    }

    func stop() async {
        // Optional: nothing for now
    }
}