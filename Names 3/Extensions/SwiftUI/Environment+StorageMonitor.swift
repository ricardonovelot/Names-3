//
//  Environment+StorageMonitor.swift
//  Names 3
//
//  Environment key for StorageMonitor so views can show "free up space" when storage is full.
//

import SwiftUI

private enum StorageMonitorKey: EnvironmentKey {
    static let defaultValue: StorageMonitor? = nil
}

extension EnvironmentValues {
    /// Inject StorageMonitor.shared at app root; default nil for previews.
    var storageMonitor: StorageMonitor? {
        get { self[StorageMonitorKey.self] }
        set { self[StorageMonitorKey.self] = newValue }
    }
}
