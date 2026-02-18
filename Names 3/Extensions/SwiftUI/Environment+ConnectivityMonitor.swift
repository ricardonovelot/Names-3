//
//  Environment+ConnectivityMonitor.swift
//  Names 3
//
//  Environment key for ConnectivityMonitor so any view can observe isOffline.
//

import SwiftUI

private enum ConnectivityMonitorKey: EnvironmentKey {
    static let defaultValue: ConnectivityMonitor? = nil
}

extension EnvironmentValues {
    /// Inject ConnectivityMonitor.shared in the app root; default nil so previews don't require it.
    var connectivityMonitor: ConnectivityMonitor? {
        get { self[ConnectivityMonitorKey.self] }
        set { self[ConnectivityMonitorKey.self] = newValue }
    }
}
