import Foundation

#if DEBUG
enum RiskySubsystem: String {
    case mediaPlayer = "MediaPlayer/Accounts"
    case avAudioSession = "AVAudioSession Reconfig"
    case networking = "Cold Networking"
}

enum StartPolicy: String {
    case onBootAfterFirstFrame = "After First Frame + App Active"
    case onActiveIdle = "When Active (idle window)"
    case onUserIntent = "On User Intent (UI)"
}

enum DebugServiceGuards {
    /// Can be called from any context; the actual gate check runs on the main actor.
    static func assertPhaseGate(_ subsystem: RiskySubsystem, policy: StartPolicy, file: StaticString = #file, line: UInt = #line) {
        Task { @MainActor in
            let isActiveOk = await PhaseGate.shared.hasReached(.appActive)
            let isFirstFrameOk = await PhaseGate.shared.hasReached(.firstFrame)
            let ok: Bool
            switch policy {
            case .onBootAfterFirstFrame:
                ok = isActiveOk && isFirstFrameOk
            case .onActiveIdle:
                ok = isActiveOk
            case .onUserIntent:
                ok = true
            }
            if !ok {
                Diagnostics.log("DEBUG GUARD: '\(subsystem.rawValue)' touched before policy '\(policy.rawValue)' (firstFrame=\(isFirstFrameOk) appActive=\(isActiveOk))")
                assertionFailure("DEBUG GUARD: '\(subsystem.rawValue)' too early")
            }
        }
    }
}
#endif