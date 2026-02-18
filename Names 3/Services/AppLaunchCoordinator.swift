//
//  AppLaunchCoordinator.swift
//  Names 3
//
//  Single owner of post-launch phases: runs services in order with signposts
//  so launch stays minimal and all deferred work is measurable in Instruments.
//

import Foundation
import SwiftData
import UIKit
import os
import os.signpost

/// Orchestrates post-launch work in phases so the first frame is not blocked.
/// Call `runPostLaunchPhases` once from WindowGroup `.task` after the window appears.
@MainActor
final class AppLaunchCoordinator {

    static let shared = AppLaunchCoordinator()

    private static let launchLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "Launch")

    private var hasRunPostLaunch = false

    private init() {
        ProcessReportCoordinator.shared.register(name: "AppLaunchCoordinator") { [weak self] in
            ProcessReportSnapshot(
                name: "AppLaunchCoordinator",
                payload: ["postLaunchRun": (self?.hasRunPostLaunch == true) ? "yes" : "no"]
            )
        }
    }

    /// Run Phase 1 (immediate), Phase 2 (UUID migration off main), then schedule Phase 3 and 4.
    /// Main thread is never blocked by Phase 2 so the app stays interactive immediately.
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

        // Phase 1a: immediate, minimal – start connectivity and CloudKit reset observer only.
        // Phase 1b (TipKit, photo observer) is deferred so the main thread stays responsive
        // while Core Data / CloudKit do WAL checkpoints and sync; otherwise Phase 1 can block 100s+.
        let state1 = LaunchProfiler.beginPhase("PostLaunchPhase1")
        LaunchProfiler.logCheckpoint("PostLaunch Phase 1 starting")
        ConnectivityMonitor.shared.start()
        LaunchProfiler.logCheckpoint("PostLaunch Phase 1 after ConnectivityMonitor")
        StorageMonitor.shared.start()
        CloudKitMirroringResetCoordinator.shared.start()
        LaunchProfiler.logCheckpoint("PostLaunch Phase 1 after CloudKitReset")
        LaunchProfiler.endPhase("PostLaunchPhase1", state1)
        LaunchProfiler.logCheckpoint("PostLaunch Phase 1 done (deferring TipKit + photo)")

        // Phase 1b: run after delay so UI and Core Data get the main thread first.
        let deferredDelay: TimeInterval = 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + deferredDelay) {
            LaunchProfiler.logCheckpoint("PostLaunch Phase 1b (TipKit + photo) starting")
            TipManager.shared.configure()
            LaunchProfiler.logCheckpoint("PostLaunch Phase 1b after TipManager")
            appDelegate.registerPhotoLibraryObserverIfNeeded()
            LaunchProfiler.logCheckpoint("PostLaunch Phase 1b done")
        }

        // Phase 2: run UUID migration and storage shrink off main so launch stays interactive (no blocking)
        let state2 = LaunchProfiler.beginPhase("PostLaunchPhase2")
        let uuidDone = UserDefaults.standard.bool(forKey: UUIDMigrationService.defaultsKey)
        let storageShrinkDone = UserDefaults.standard.bool(forKey: StorageShrinkMigrationService.defaultsKey)
        if uuidDone && storageShrinkDone {
            LaunchProfiler.endPhase("PostLaunchPhase2", state2)
            LaunchProfiler.logCheckpoint("PostLaunch Phase 2 (migrations) skipped – already done")
            LaunchProfiler.markTimeToInteractive()
        } else {
            LaunchProfiler.logCheckpoint("PostLaunch Phase 2 (migrations) running in background")
            LaunchProfiler.endPhase("PostLaunchPhase2", state2)
            Task.detached(priority: .userInitiated) {
                let context = ModelContext(modelContainer)

                if !uuidDone {
                    if UUIDMigrationService.isStoreEmpty(context: context) {
                        await MainActor.run {
                            UserDefaults.standard.set(true, forKey: UUIDMigrationService.defaultsKey)
                            Self.launchLogger.info("🚀 [Launch] UUID migration skipped – store empty, marking done")
                            LaunchProfiler.logCheckpoint("UUID migration (background) skipped – store empty")
                        }
                    } else {
                        let anyFixed = UUIDMigrationService.runMigration(context: context)
                        await MainActor.run {
                            UserDefaults.standard.set(true, forKey: UUIDMigrationService.defaultsKey)
                            LaunchProfiler.logCheckpoint("UUID migration (background) finished, anyFixed=\(anyFixed)")
                        }
                    }
                }

                if !storageShrinkDone {
                    if StorageShrinkMigrationService.isStoreEmpty(context: context) {
                        await MainActor.run {
                            UserDefaults.standard.set(true, forKey: StorageShrinkMigrationService.defaultsKey)
                            LaunchProfiler.logCheckpoint("Storage shrink (background) skipped – store empty")
                        }
                    } else {
                        let (contacts, embeddings) = StorageShrinkMigrationService.runMigration(context: context)
                        await MainActor.run {
                            UserDefaults.standard.set(true, forKey: StorageShrinkMigrationService.defaultsKey)
                            LaunchProfiler.logCheckpoint("Storage shrink (background) finished, contacts=\(contacts), embeddings=\(embeddings)")
                        }
                    }
                }
            }
            // TTI = main thread is free (Phase 2 runs in background, does not block)
            LaunchProfiler.markTimeToInteractive()
        }

        // Phase 3: onboarding check after 1 s (edge case: e.g. onboarding reset from Settings).
        // First-launch onboarding is shown by LaunchRootView via OnboardingGateView, so the main
        // app is never shown empty; Phase 3 may no-op if onboarding is already active.
        LaunchProfiler.logCheckpoint("PostLaunch Phase 3 scheduled in 1s")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            Task { @MainActor in
                self?.runPhase3Onboarding(modelContainer: modelContainer)
            }
        }

        LaunchProfiler.logCheckpoint("PostLaunch orchestration finished")
    }

    private func runPhase3Onboarding(modelContainer: ModelContainer) {
        let state3 = LaunchProfiler.beginPhase("PostLaunchPhase3")
        LaunchProfiler.logCheckpoint("PostLaunch Phase 3 (onboarding) starting")
        defer {
            LaunchProfiler.endPhase("PostLaunchPhase3", state3)
            LaunchProfiler.logCheckpoint("PostLaunch Phase 3 done")
        }
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            Self.launchLogger.error("🚀 [Launch] No window for onboarding")
            return
        }
        let modelContext = ModelContext(modelContainer)
        OnboardingCoordinatorManager.shared.showOnboarding(
            in: window,
            forced: false,
            modelContext: modelContext
        )
    }
}
