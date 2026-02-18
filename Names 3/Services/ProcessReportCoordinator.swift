//
//  ProcessReportCoordinator.swift
//  Names 3
//
//  Central process reporting: every service reports its state on demand.
//  Used for memory debugging and diagnostics. Triggered on memory warning
//  and optionally on background. Every dump includes ProcessMemory (processMemoryMB).
//  To see current memory anytime: Debug → Simulate Memory Warning, or send app to background. Senior pattern: single pipeline, structured
//  payloads, os_log for Console filtering.
//

import Foundation
import os.log
import UIKit

// MARK: - Snapshot

/// One service's reported state. Payload keys are arbitrary; use consistent names for parsing.
struct ProcessReportSnapshot {
    let name: String
    let payload: [String: String]
    
    init(name: String, payload: [String: String] = [:]) {
        self.name = name
        self.payload = payload
    }
    
    /// Single-line string for logging: name k1=v1 k2=v2
    var logLine: String {
        let pairs = payload.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        return pairs.isEmpty ? name : "\(name) \(pairs)"
    }
}

// MARK: - Coordinator

private let processReportLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Names3",
    category: "ProcessReport"
)

/// Central coordinator for process reports. Services register a closure that returns their current state.
/// Call `reportAll(trigger:)` to dump every registered report (e.g. on memory warning).
final class ProcessReportCoordinator {
    static let shared = ProcessReportCoordinator()
    
    private let lock = NSLock()
    private var contributors: [(name: String, report: () -> ProcessReportSnapshot)] = []
    
    private init() {
        registerStatelessReporters()
        observeMemoryWarning()
        observeEnterBackground()
    }

    /// Stateless or utility services that don't have a singleton; report fixed state.
    private func registerStatelessReporters() {
        register(name: "ProcessMemory") {
            let mb = ProcessMemoryReporter.currentMegabytes()
            let value = mb.map { String(format: "%.1f", $0) } ?? "?"
            return ProcessReportSnapshot(name: "ProcessMemory", payload: ["processMemoryMB": value])
        }
        register(name: "FaceAnalysisCache") {
            ProcessReportSnapshot(name: "FaceAnalysisCache", payload: ["state": "SwiftData queries only"])
        }
        register(name: "ImageDecodingService") {
            ProcessReportSnapshot(name: "ImageDecodingService", payload: ["state": "decode queue"])
        }
        register(name: "NameFacesMemory") {
            ProcessReportSnapshot(name: "NameFacesMemory", payload: ["state": "UserDefaults", "maxAssets": "100"])
        }
        register(name: "UUIDMigrationService") {
            ProcessReportSnapshot(name: "UUIDMigrationService", payload: ["state": "one-time migration"])
        }
    }
    
    /// Register a contributor. Call from service init. Closure is invoked on reportAll (may be called from any queue).
    func register(name: String, report: @escaping () -> ProcessReportSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        contributors.append((name: name, report: report))
        processReportLogger.debug("Registered process reporter: \(name)")
    }
    
    /// Unregister by name (e.g. when a VC or short-lived owner deallocates). Removes all contributors with that name.
    func unregister(name: String) {
        lock.lock()
        defer { lock.unlock() }
        contributors.removeAll { $0.name == name }
    }
    
    /// Collect and log all reports. Safe to call from any queue. Use trigger to mark why (e.g. "memory_warning", "background").
    func reportAll(trigger: String = "manual") {
        lock.lock()
        let list = contributors
        lock.unlock()
        
        processReportLogger.info("[ProcessReport] trigger=\(trigger) count=\(list.count)")
        for item in list {
            let snapshot = item.report()
            processReportLogger.info("[ProcessReport] \(snapshot.logLine)")
        }
    }
    
    private func observeMemoryWarning() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reportAll(trigger: "memory_warning")
        }
    }

    private func observeEnterBackground() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reportAll(trigger: "background")
        }
    }
}
