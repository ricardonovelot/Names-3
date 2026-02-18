//
//  LaunchProfiler.swift
//  Names 3
//
//  Apple-recommended launch profiling: OSSignposter for Instruments (Points of Interest)
//  and time-to-interactive (TTI) for the critical path. Use at scale for debugging and metrics.
//

import Foundation
import os
import os.signpost

/// Central launch and background profiling for Instruments and logs.
/// - Use OSSignposter intervals so phases show in Instruments → Points of Interest.
/// - Call `markProcessStart()` in App init, `markLaunchStart()` when post-launch task runs, `markTimeToInteractive()` when main UI is ready.
/// - Use `logCheckpoint(_:)` for visibility: every message includes elapsed time since process start.
enum LaunchProfiler {

    private static let subsystem = Bundle.main.bundleIdentifier ?? "Names3"
    private static let launchLog = OSLog(subsystem: subsystem, category: "Launch")
    private static let backgroundLog = OSLog(subsystem: subsystem, category: "Background")

    static let launchLogger = Logger(subsystem: subsystem, category: "Launch")
    static let backgroundLogger = Logger(subsystem: subsystem, category: "Background")

    /// Process start (first thing in App init). Every checkpoint can log elapsed since this.
    private static var _processStartTime: CFAbsoluteTime?
    /// Post-launch task start (when LaunchRootView.task runs). TTI is measured from this.
    private static var _launchStartTime: CFAbsoluteTime?
    static var launchStartTime: CFAbsoluteTime? { _launchStartTime }

    /// Call from App.init so we have a single "process start" for all elapsed logs.
    static func markProcessStart() {
        if _processStartTime == nil {
            _processStartTime = CFAbsoluteTimeGetCurrent()
            logCheckpoint("Process start (timer started)")
        }
    }

    /// Elapsed seconds since process start. Use in checkpoint logs to see where time is spent.
    static func elapsedSinceProcessStart() -> String {
        guard let t0 = _processStartTime else { return "?" }
        return String(format: "%.3f", CFAbsoluteTimeGetCurrent() - t0)
    }

    /// Log a launch checkpoint with elapsed time since process start. Use everywhere you need visibility.
    static func logCheckpoint(_ message: String) {
        launchLogger.info("🚀 [Launch] [+\(elapsedSinceProcessStart())s] \(message)")
    }

    /// Call when post-launch task begins (LaunchRootView.task). Starts TTI timer.
    static func markLaunchStart() {
        _launchStartTime = CFAbsoluteTimeGetCurrent()
        logCheckpoint("Post-launch task started (TTI timer started)")
    }

    /// Call when the main UI is ready for interaction.
    /// Logs time-to-interactive and emits a signpost for Instruments.
    static func markTimeToInteractive() {
        guard let t0 = _launchStartTime else { return }
        let tti = CFAbsoluteTimeGetCurrent() - t0
        launchLogger.info("🚀 [Launch] [+\(elapsedSinceProcessStart())s] Time to interactive: \(String(format: "%.3f", tti))s (since task start)")
        signposter.emitEvent("LaunchComplete")
    }

    /// Signposter for Launch category. Use beginInterval/endInterval for phases.
    private static let signposter = OSSignposter(logHandle: launchLog)

    // MARK: - Named phases (StaticString for OSSignposter)

    /// Start a named interval. Call `endPhase` with the same name and the returned state.
    static func beginPhase(_ name: StaticString) -> OSSignpostIntervalState {
        return signposter.beginInterval(name)
    }

    /// End a named interval. Pass the state returned from `beginPhase`.
    static func endPhase(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    /// Emit a point-in-time event (e.g. "LaunchComplete").
    static func emitEvent(_ name: StaticString) {
        signposter.emitEvent(name)
    }

    // MARK: - Thread-aware logging helper

    /// "main=YES" or "main=NO" for inclusion in launch/background logs.
    static var mainThreadTag: String { "main=\(Thread.isMainThread)" }
}
