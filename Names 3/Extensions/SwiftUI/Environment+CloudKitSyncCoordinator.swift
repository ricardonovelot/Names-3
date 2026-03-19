//
//  Environment+CloudKitSyncCoordinator.swift
//  Names 3
//
//  Environment key for CloudKitSyncCoordinator so views can use syncRefreshTrigger
//  to force @Query re-evaluation when CloudKit syncs remote changes.
//

import SwiftUI

private enum CloudKitSyncCoordinatorKey: EnvironmentKey {
    static let defaultValue: CloudKitSyncCoordinator? = nil
}

extension EnvironmentValues {
    /// Inject CloudKitSyncCoordinator.shared at app root; default nil for previews.
    var cloudKitSyncCoordinator: CloudKitSyncCoordinator? {
        get { self[CloudKitSyncCoordinatorKey.self] }
        set { self[CloudKitSyncCoordinatorKey.self] = newValue }
    }
}
