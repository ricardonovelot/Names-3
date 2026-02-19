import Foundation
import UIKit

enum LaunchPhase: Int {
    case appInit
    case firstFrame
    case appActive
    case firstVideoReady
}

actor PhaseGate {
    static let shared = PhaseGate()
    private var reached: Set<LaunchPhase> = [.appInit]

    func mark(_ phase: LaunchPhase) {
        reached.insert(phase)
        Diagnostics.log("PhaseGate mark \(phase)")
    }

    func hasReached(_ phase: LaunchPhase) -> Bool { reached.contains(phase) }

    func waitUntil(_ phase: LaunchPhase, timeout: TimeInterval = 5) async -> Bool {
        let t0 = Date()
        while !reached.contains(phase) {
            try? await Task.sleep(for: .milliseconds(50))
            if Date().timeIntervalSince(t0) > timeout {
                Diagnostics.log("PhaseGate wait timeout \(phase)")
                return false
            }
        }
        return true
    }

    func waitUntilAppActive(timeout: TimeInterval = 5) async -> Bool {
        let t0 = Date()
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(60))
            if Date().timeIntervalSince(t0) > timeout {
                Diagnostics.log("PhaseGate wait appActive timeout")
                return false
            }
        }
        return true
    }
}