//
//  CloudKitSyncCoordinator.swift
//  Names 3
//
//  Coordinates SwiftData + CloudKit sync awareness across the app. Observes remote
//  store changes, app lifecycle, and CloudKit events to trigger instant UI refresh
//  for contacts, albums, notes, and journal. Ensures data added on one device appears
//  promptly on others.
//

import Foundation
import SwiftData
import UIKit
import CoreData
import os

// MARK: - Sync Notifications

extension Notification.Name {
    /// Posted when CloudKit sync brings in remote changes. Contacts feed, albums, notes, journal should refresh.
    static let cloudKitSyncDidImportChanges = Notification.Name("Names3.CloudKitSyncDidImportChanges")
}

// MARK: - CloudKitSyncCoordinator

/// Observes CloudKit sync events and triggers UI refresh so contacts, albums, and other
/// SwiftData-backed data update promptly when changes arrive from other devices.
@MainActor
final class CloudKitSyncCoordinator: ObservableObject {

    static let shared = CloudKitSyncCoordinator()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Names3",
        category: "CloudKitSync"
    )

    /// Incremented when remote sync completes. Views can use .id(syncRefreshTrigger) to force @Query re-evaluation.
    @Published private(set) var syncRefreshTrigger: Int = 0

    private weak var modelContainer: ModelContainer?
    private var remoteChangeObserver: NSObjectProtocol?
    private var cloudKitEventObserver: NSObjectProtocol?
    private var becomeActiveObserver: NSObjectProtocol?
    private var periodicRefreshTask: Task<Void, Never>?
    private var lastRefreshTime: Date = .distantPast
    private let minRefreshInterval: TimeInterval = 1.0
    private let periodicRefreshInterval: TimeInterval = 60.0

    private init() {}

    /// Call once when ModelContainer is ready. Starts observing sync events.
    func configure(container: ModelContainer) {
        guard modelContainer == nil else { return }
        modelContainer = container

        observeRemoteStoreChanges()
        observeCloudKitEvents()
        observeAppBecomeActive()
        startPeriodicRefresh()
    }

    // Singleton — never deallocates during app lifetime; no deinit needed.

    // MARK: - Observation

    private func observeRemoteStoreChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleRemoteSync()
            }
        }
        Self.logger.debug("CloudKitSyncCoordinator: observing NSPersistentStoreRemoteChange")
    }

    private func observeCloudKitEvents() {
        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleCloudKitEvent(notification)
            }
        }
        Self.logger.debug("CloudKitSyncCoordinator: observing NSPersistentCloudKitContainer.eventChangedNotification")
    }

    private func observeAppBecomeActive() {
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAppBecameActive()
            }
        }
        Self.logger.debug("CloudKitSyncCoordinator: observing didBecomeActive")
    }

    private func startPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(periodicRefreshInterval))
                guard !Task.isCancelled else { break }
                await handlePeriodicRefresh()
            }
        }
        Self.logger.debug("CloudKitSyncCoordinator: periodic refresh every \(self.periodicRefreshInterval)s")
    }

    // MARK: - Handlers

    private func handleRemoteSync() {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshTime) >= minRefreshInterval else {
            return
        }
        lastRefreshTime = now
        Self.logger.info("CloudKitSyncCoordinator: NSPersistentStoreRemoteChange — refreshing UI")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            performRefresh()
        }
    }

    private func handleCloudKitEvent(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let event = userInfo[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }
        if event.endDate != nil {
            let now = Date()
            guard now.timeIntervalSince(lastRefreshTime) >= minRefreshInterval else { return }
            lastRefreshTime = now
            Self.logger.info("CloudKitSyncCoordinator: CloudKit import completed — refreshing UI")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                performRefresh()
            }
        }
    }

    private func handleAppBecameActive() {
        Self.logger.debug("CloudKitSyncCoordinator: app became active — refreshing for any sync while backgrounded")
        performRefresh()
    }

    private func handlePeriodicRefresh() async {
        guard UIApplication.shared.applicationState == .active else { return }
        Self.logger.debug("CloudKitSyncCoordinator: periodic refresh")
        performRefresh()
    }

    // MARK: - Refresh

    private func performRefresh() {
        syncRefreshTrigger += 1
        NotificationCenter.default.post(name: .contactsDidChange, object: nil)
        NotificationCenter.default.post(name: .cloudKitSyncDidImportChanges, object: nil)
        AlbumStore.shared.refreshFromRemoteSync()
    }
}
