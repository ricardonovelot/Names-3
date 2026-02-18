//
//  CloudKitMirroringResetCoordinator.swift
//  Names 3
//
//  Observes CoreData+CloudKit mirroring reset (e.g. persistent history token expired).
//  All state is updated on the main queue so SwiftUI never sees "Publishing changes from background threads".
//  Use isSyncResetInProgress to avoid reading model relationships (e.g. Tag.name) that may be invalidated.
//

import Foundation
import Combine
import os

/// Notification name posted by CoreData+CloudKit when sync will reset (e.g. history token expired).
/// Observers must only update UI state on the main queue.
public let NSCloudKitMirroringDelegateWillResetSyncNotificationName = Notification.Name("NSCloudKitMirroringDelegateWillResetSyncNotificationName")

/// Coordinates UI response to CloudKit mirroring reset. Start once at app launch; observe isSyncResetInProgress
/// to show safe (date-only) group titles and avoid touching invalidated model objects.
@MainActor
@Observable
final class CloudKitMirroringResetCoordinator {
    static let shared = CloudKitMirroringResetCoordinator()

    /// True from when we receive WillResetSync until a short delay after. When true, avoid reading Tag/Contact
    /// relationships that may be invalidated; show date-only titles instead of tag-based titles.
    private(set) var isSyncResetInProgress: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "CloudKitReset")
    /// Delay after reset notification before we consider sync stable enough to read tag names again.
    private static let resetCooldownSeconds: TimeInterval = 2.5

    private init() {
        ProcessReportCoordinator.shared.register(name: "CloudKitMirroringResetCoordinator") { [weak self] in
            let inProgress = self?.isSyncResetInProgress ?? false
            return ProcessReportSnapshot(
                name: "CloudKitMirroringResetCoordinator",
                payload: ["syncResetInProgress": inProgress ? "yes" : "no"]
            )
        }
    }

    /// Call once at app launch (e.g. from App or AppLaunchCoordinator). Subscribes to CoreData notification
    /// and ensures all updates run on the main queue.
    func start() {
        NotificationCenter.default.publisher(for: NSCloudKitMirroringDelegateWillResetSyncNotificationName)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleWillResetSync()
            }
            .store(in: &cancellables)
        Self.logger.debug("CloudKit mirroring reset coordinator started (observing on main queue)")
    }

    private func handleWillResetSync() {
        assert(Thread.isMainThread, "Handler must run on main thread")
        Self.logger.info("CloudKit mirroring will reset (e.g. history token expired); entering safe mode")
        isSyncResetInProgress = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resetCooldownSeconds) { [weak self] in
            guard let self else { return }
            assert(Thread.isMainThread, "Cooldown must run on main thread")
            self.isSyncResetInProgress = false
            Self.logger.debug("CloudKit reset cooldown finished; safe mode off")
        }
    }
}
