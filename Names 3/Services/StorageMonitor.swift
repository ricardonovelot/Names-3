//
//  StorageMonitor.swift
//  Names 3
//
//  Monitors device storage so the app can show "Not syncing — storage full" when
//  there isn't enough space for SwiftData/CloudKit or local saves.
//

import Foundation
import os

/// Threshold below which we consider the device "low on storage" (sync and saves may fail).
/// Apple recommends using volumeAvailableCapacityForImportantUsageKey for "can the system grant space for important work."
/// 100 MB gives earlier warning before writes start failing with ENOSPC.
private let lowStorageThresholdBytes: Int64 = 100 * 1024 * 1024  // 100 MB

/// Observable device storage state. Start at app launch; check runs off main and updates on main.
@MainActor
@Observable
final class StorageMonitor {
    static let shared = StorageMonitor()

    /// True when free space is below threshold; show "free up space" message so users know why sync may not work.
    private(set) var isLowOnDeviceStorage: Bool = false

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "Storage")

    private init() {
        ProcessReportCoordinator.shared.register(name: "StorageMonitor") { [weak self] in
            guard let self else {
                return ProcessReportSnapshot(name: "StorageMonitor", payload: ["state": "released"])
            }
            return ProcessReportSnapshot(
                name: "StorageMonitor",
                payload: ["lowStorage": self.isLowOnDeviceStorage ? "yes" : "no"]
            )
        }
    }

    /// Call once at app launch. Safe to call multiple times. Runs check asynchronously.
    func start() {
        checkStorageAsync()
    }

    /// Call when app becomes active (e.g. scenePhase .active) to refresh after user frees space.
    func refreshIfNeeded() {
        checkStorageAsync()
    }

    /// Call when a save fails with ENOSPC (code 28) to immediately show the storage-full message
    /// without waiting for the next async check.
    func reportLowStorage() {
        if !isLowOnDeviceStorage {
            isLowOnDeviceStorage = true
            Self.logger.info("Storage reported low (e.g. ENOSPC during save)")
        }
    }

    /// Call with a save error; if it's ENOSPC, immediately reports low storage. Safe to call from any context.
    static nonisolated func reportIfENOSPC(_ error: Error) {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain && ns.code == 28 {
            Task { @MainActor in
                shared.reportLowStorage()
            }
        }
    }

    private func checkStorageAsync() {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let isLow = await Self.checkIsLowStorage()
            await MainActor.run {
                if self.isLowOnDeviceStorage != isLow {
                    self.isLowOnDeviceStorage = isLow
                    Self.logger.info("Storage state changed: isLowOnDeviceStorage=\(isLow)")
                }
            }
        }
    }

    /// Runs on arbitrary thread. Returns true when free space is below threshold.
    private static func checkIsLowStorage() -> Bool {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            guard let capacity = values.volumeAvailableCapacityForImportantUsage else {
                return false
            }
            return capacity < lowStorageThresholdBytes
        } catch {
            logger.warning("Could not read volume capacity: \(error.localizedDescription)")
            return false
        }
    }
}
