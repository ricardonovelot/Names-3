//
//  Environment+CloudKitMirroringResetCoordinator.swift
//  Names 3
//
//  Environment key for CloudKitMirroringResetCoordinator so views can observe isSyncResetInProgress.
//

import SwiftUI

private enum CloudKitMirroringResetCoordinatorKey: EnvironmentKey {
    static let defaultValue: CloudKitMirroringResetCoordinator? = nil
}

extension EnvironmentValues {
    /// Inject CloudKitMirroringResetCoordinator.shared at app root; default nil for previews.
    var cloudKitMirroringResetCoordinator: CloudKitMirroringResetCoordinator? {
        get { self[CloudKitMirroringResetCoordinatorKey.self] }
        set { self[CloudKitMirroringResetCoordinatorKey.self] = newValue }
    }
}
