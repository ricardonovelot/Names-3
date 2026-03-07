//
//  ConnectivityMonitor.swift
//  Names 3
//
//  Monitors network path via NWPathMonitor. Exposes isOffline for UI (banners, alerts).
//  Start on app launch; updates are delivered on the main queue for SwiftUI.
//

import Foundation
import Network
import os

/// Nonisolated storage for cellular state, readable from any context (e.g. feed media loaders).
private enum ConnectivityCellularCache {
    static let lock = NSLock()
    static var usesCellular = false
}

/// Observable connectivity state. Start once (e.g. in App); observe isOffline for banners/alerts.
@MainActor
@Observable
final class ConnectivityMonitor {
    static let shared = ConnectivityMonitor()

    /// True when no network path is available (offline). Use for banners and contextual alerts.
    private(set) var isOffline: Bool = false

    /// Optional: constrained = cellular only (no WiFi). Use if you need to distinguish "limited" vs "none".
    private(set) var isConstrained: Bool = false

    /// True when the current path uses cellular (e.g. LTE/5G). Use to warn about data usage when viewing videos.
    private(set) var usesCellular: Bool = false

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.names3.connectivity", qos: .utility)
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "Connectivity")

    private let reportLock = NSLock()
    private var _reportOffline = false
    private var _reportConstrained = false
    private var _reportUsesCellular = false

    /// Thread-safe cached value for reading from non-MainActor contexts (e.g. feed media loaders).
    nonisolated static var cachedUsesCellular: Bool {
        ConnectivityCellularCache.lock.lock()
        defer { ConnectivityCellularCache.lock.unlock() }
        return ConnectivityCellularCache.usesCellular
    }

    private init() {
        self.monitor = NWPathMonitor()
        ProcessReportCoordinator.shared.register(name: "ConnectivityMonitor") { [weak self] in
            guard let self else {
                return ProcessReportSnapshot(name: "ConnectivityMonitor", payload: ["state": "released"])
            }
            self.reportLock.lock()
            let offline = self._reportOffline
            let constrained = self._reportConstrained
            let cellular = self._reportUsesCellular
            self.reportLock.unlock()
            return ProcessReportSnapshot(
                name: "ConnectivityMonitor",
                payload: ["isOffline": offline ? "yes" : "no", "isConstrained": constrained ? "yes" : "no", "usesCellular": cellular ? "yes" : "no"]
            )
        }
    }

    /// Call once at app launch (e.g. from App init or .onAppear). Safe to call multiple times; starts monitoring.
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = self.isOffline
                self.isOffline = (path.status != .satisfied)
                self.isConstrained = path.isConstrained
                self.usesCellular = path.usesInterfaceType(.cellular)
                self.reportLock.lock()
                self._reportOffline = self.isOffline
                self._reportConstrained = self.isConstrained
                self._reportUsesCellular = self.usesCellular
                self.reportLock.unlock()
                ConnectivityCellularCache.lock.lock()
                ConnectivityCellularCache.usesCellular = self.usesCellular
                ConnectivityCellularCache.lock.unlock()
                if self.isOffline != wasOffline {
                    Self.logger.info("Connectivity changed: isOffline=\(self.isOffline), constrained=\(self.isConstrained), usesCellular=\(self.usesCellular)")
                }
            }
        }
        monitor.start(queue: queue)
        Self.logger.debug("ConnectivityMonitor started")
    }

    /// Optional: stop when not needed (e.g. background). Not required for normal foreground use.
    func stop() {
        monitor.cancel()
        Self.logger.debug("ConnectivityMonitor stopped")
    }
}
