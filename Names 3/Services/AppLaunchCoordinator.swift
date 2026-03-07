//
//  AppLaunchCoordinator.swift
//  Names 3
//
//  Single owner of post-launch service startup. Runs in strict phases so every
//  millisecond is measurable in Instruments → Points of Interest.
//
//  Call site: Names_3App.task, ONCE, after ModelContainer is created and BEFORE
//  modelContainer is published to the UI. This guarantees all services are live
//  the moment any view appears — for both returning users AND new users in onboarding.
//

import Foundation
import SwiftData
import UIKit
import os
import os.signpost

/// Orchestrates post-launch service startup in phases.
///
/// **Phase 1a** (sync, <1 ms): Start ConnectivityMonitor, StorageMonitor, CloudKitReset.
/// **Phase 1b** (sync, ~5 ms): Configure TipKit, register photo-library observer.
/// **Phase 2**  (async, background): UUID migration + storage-shrink migration — never blocks UI.
/// **Phase 3**  (sync): Onboarding edge-case gate (e.g. onboarding reset from Settings).
@MainActor
final class AppLaunchCoordinator {

    static let shared = AppLaunchCoordinator()

    private static let launchLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Names3",
        category: "Launch"
    )

    /// Guards against running phases more than once per process lifetime.
    private(set) var hasRunPostLaunch = false

    private init() {
        ProcessReportCoordinator.shared.register(name: "AppLaunchCoordinator") { [weak self] in
            ProcessReportSnapshot(
                name: "AppLaunchCoordinator",
                payload: ["postLaunchRun": (self?.hasRunPostLaunch == true) ? "yes" : "no"]
            )
        }
    }

    /// Start all services and run background migrations.
    ///
    /// - This is `async` so callers can `await` it before publishing the `ModelContainer` to the UI,
    ///   guaranteeing services are ready before any view renders.
    /// - Phase 2 is fire-and-forget (`Task.detached`) so this function returns in ~5 ms.
    /// - Idempotent: subsequent calls are no-ops (guarded by `hasRunPostLaunch`).
    func runPostLaunchPhases(
        modelContainer: ModelContainer,
        appDelegate: AppDelegate
    ) async {
        guard !hasRunPostLaunch else {
            Self.launchLogger.info("🚀 [Launch] PostLaunch already run, skipping")
            return
        }
        hasRunPostLaunch = true

        LaunchProfiler.markLaunchStart()
        LaunchProfiler.logCheckpoint("PostLaunch orchestration started (\(LaunchProfiler.mainThreadTag))")

        // MARK: Phase 1a — Core services (sync, ~1 ms)
        // Keep this minimal: ConnectivityMonitor and StorageMonitor are needed immediately.
        // CloudKitReset is lightweight to start.
        let phase1State = LaunchProfiler.beginPhase("PostLaunchPhase1")
        ConnectivityMonitor.shared.start()
        StorageMonitor.shared.start()
        CloudKitMirroringResetCoordinator.shared.start()
        LaunchProfiler.endPhase("PostLaunchPhase1", phase1State)
        LaunchProfiler.logCheckpoint("PostLaunch Phase 1 done")

        // MARK: Phase 1b — Deferred startup (sync, ~5 ms)
        // TipKit and photo-library observer are deferred from Phase 1a to keep the
        // critical path as short as possible; they are still safe to run before UI appears.
        let phase1bState = LaunchProfiler.beginPhase("PostLaunchPhase1b")
        TipManager.shared.configure()
        appDelegate.registerPhotoLibraryObserverIfNeeded()
        LaunchProfiler.endPhase("PostLaunchPhase1b", phase1bState)
        LaunchProfiler.logCheckpoint("PostLaunch Phase 1b done")

        // MARK: Phase 2 — Background migrations (async, fire-and-forget)
        // Never blocks the main thread. Runs on a background priority thread.
        let uuidDone = UserDefaults.standard.bool(forKey: UUIDMigrationService.defaultsKey)
        let storageShrinkDone = UserDefaults.standard.bool(forKey: StorageShrinkMigrationService.defaultsKey)

        if uuidDone && storageShrinkDone {
            LaunchProfiler.logCheckpoint("PostLaunch Phase 2 skipped – all migrations already done")
            LaunchProfiler.markTimeToInteractive()
        } else {
            LaunchProfiler.logCheckpoint("PostLaunch Phase 2 – migrations queued on background thread")
            Task.detached(priority: .userInitiated) {
                await Self.runBackgroundMigrations(
                    modelContainer: modelContainer,
                    uuidDone: uuidDone,
                    storageShrinkDone: storageShrinkDone
                )
            }
            LaunchProfiler.markTimeToInteractive()
        }

        // MARK: Phase 3 — Onboarding edge-case gate
        // Handles the case where onboarding was reset from Settings (e.g. QA / re-onboarding flows).
        runPhase3OnboardingGate(modelContainer: modelContainer)

        LaunchProfiler.logCheckpoint("PostLaunch orchestration finished")
    }

    // MARK: - Private

    private static func runBackgroundMigrations(
        modelContainer: ModelContainer,
        uuidDone: Bool,
        storageShrinkDone: Bool
    ) async {
        let context = ModelContext(modelContainer)

        if !uuidDone {
            if UUIDMigrationService.isStoreEmpty(context: context) {
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: UUIDMigrationService.defaultsKey)
                    LaunchProfiler.logCheckpoint("UUID migration skipped – store empty")
                }
            } else {
                let anyFixed = UUIDMigrationService.runMigration(context: context)
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: UUIDMigrationService.defaultsKey)
                    LaunchProfiler.logCheckpoint("UUID migration finished, anyFixed=\(anyFixed)")
                }
            }
        }

        if !storageShrinkDone {
            if StorageShrinkMigrationService.isStoreEmpty(context: context) {
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: StorageShrinkMigrationService.defaultsKey)
                    LaunchProfiler.logCheckpoint("Storage shrink skipped – store empty")
                }
            } else {
                let (contacts, embeddings) = StorageShrinkMigrationService.runMigration(context: context)
                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: StorageShrinkMigrationService.defaultsKey)
                    LaunchProfiler.logCheckpoint("Storage shrink finished, contacts=\(contacts), embeddings=\(embeddings)")
                }
            }
        }
    }

    private func runPhase3OnboardingGate(modelContainer: ModelContainer) {
        let phase3State = LaunchProfiler.beginPhase("PostLaunchPhase3")
        defer { LaunchProfiler.endPhase("PostLaunchPhase3", phase3State) }

        // Prefer the foreground-active scene; fall back to first available.
        let targetScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.first
        guard let windowScene = targetScene as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
                ?? windowScene.windows.first else {
            Self.launchLogger.error("🚀 [Launch] Phase 3: no window available for onboarding check")
            return
        }

        let modelContext = ModelContext(modelContainer)
        OnboardingCoordinatorManager.shared.showOnboarding(
            in: window,
            forced: false,
            modelContext: modelContext
        )
        LaunchProfiler.logCheckpoint("PostLaunch Phase 3 done")
    }
}
