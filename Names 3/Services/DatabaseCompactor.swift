//
//  DatabaseCompactor.swift
//  Names 3
//
//  Compacts SQLite store (checkpoint + vacuum) to reclaim storage.
//

import Foundation
import SQLite3
import SwiftData
import os

enum DatabaseCompactor {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "DatabaseCompactor")

    /// Store names used by the app (CloudKit default, local fallback).
    private static let storeNames = ["default", "local-fallback"]

    /// Compact main database stores. Saves context first; runs checkpoint then vacuum.
    /// Returns bytes freed (approximate) or nil on failure.
    static func compact(modelContext: ModelContext) -> Int64? {
        modelContext.processPendingChanges()
        try? modelContext.save()

        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        var totalFreed: Int64 = 0
        for name in storeNames {
            let storeURL = appSupport.appendingPathComponent("\(name).store")
            guard FileManager.default.fileExists(atPath: storeURL.path) else { continue }
            if let freed = compactStore(at: storeURL) {
                totalFreed += freed
            }
        }
        return totalFreed
    }

    private static func compactStore(at url: URL) -> Int64? {
        let before = fileSize(url)
        let walURL = URL(fileURLWithPath: url.path + "-wal")
        let shmURL = URL(fileURLWithPath: url.path + "-shm")
        let beforeWAL = fileSize(walURL)
        let beforeSHM = fileSize(shmURL)

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK, let db else {
            let err = String(cString: sqlite3_errmsg(db))
            logger.warning("Could not open store for compact: \(err, privacy: .public)")
            if let d = db { sqlite3_close(d) }
            return nil
        }
        defer { sqlite3_close(db) }

        sqlite3_busy_timeout(db, 30_000)

        if sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil) != SQLITE_OK {
            let err = String(cString: sqlite3_errmsg(db))
            logger.warning("Checkpoint failed: \(err, privacy: .public)")
        }

        if sqlite3_exec(db, "VACUUM;", nil, nil, nil) != SQLITE_OK {
            let err = String(cString: sqlite3_errmsg(db))
            logger.warning("VACUUM failed: \(err, privacy: .public)")
        }

        let after = fileSize(url)
        let afterWAL = fileSize(walURL)
        let afterSHM = fileSize(shmURL)
        let freed = (before - after) + (beforeWAL - afterWAL) + (beforeSHM - afterSHM)
        if freed > 0 {
            logger.info("Compacted store: freed \(freed) bytes")
        }
        return max(0, freed)
    }

    private static func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
    }
}
