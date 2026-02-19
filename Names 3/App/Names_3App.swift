//
//  Names_3App.swift
//  Names 3
//
//  Created by Ricardo on 14/10/24.
//

import SwiftUI
import SwiftData
import UIKit
import os
import TipKit
import os.signpost

@main
struct Names_3App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    /// Bootstraps PhaseGate for Video Feed (AVAudioSession, MediaPlayer guards).
    private let feedLifecycleMonitor = AppLifecycleMonitor()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "SwiftData")
    private static let launchLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "Launch")

    init() {
        LaunchProfiler.markProcessStart()
        Self.launchLogger.info("🚀 [Launch] [+\(LaunchProfiler.elapsedSinceProcessStart())s] App init (\(LaunchProfiler.mainThreadTag))")
    }

    var sharedModelContainer: ModelContainer = {
        let t0 = CFAbsoluteTimeGetCurrent()
        let signpostState = LaunchProfiler.beginPhase("ModelContainerCreation")
        Names_3App.launchLogger.info("🚀 [Launch] ModelContainer creation started (\(LaunchProfiler.mainThreadTag))")
        let schema = Schema([
            Contact.self,
            Note.self,
            Tag.self,
            QuickNote.self,
            QuizSession.self,
            QuizPerformance.self,
            NoteRehearsalPerformance.self,
            FaceEmbedding.self,
            FaceCluster.self,
            DeletedPhoto.self,
        ])

        let cloudConfig = ModelConfiguration(
            "default",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.ricardo.Names4")
        )

        do {
            Names_3App.logger.info("Initializing SwiftData container with CloudKit")
            let container = try ModelContainer(
                for: schema,
                migrationPlan: Names3SchemaMigrationPlan.self,
                configurations: [cloudConfig]
            )
            let elapsed = CFAbsoluteTimeGetCurrent() - t0
            LaunchProfiler.endPhase("ModelContainerCreation", signpostState)
            Names_3App.launchLogger.info("🚀 [Launch] ModelContainer (CloudKit) created in \(String(format: "%.3f", elapsed))s")
            return container
        } catch {
            Names_3App.logger.error("CloudKit ModelContainer init failed: \(error, privacy: .public). Falling back to local store.")
            let localConfig = ModelConfiguration(
                "local-fallback",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            do {
                let container = try ModelContainer(
                    for: schema,
                    migrationPlan: Names3SchemaMigrationPlan.self,
                    configurations: [localConfig]
                )
                let elapsed = CFAbsoluteTimeGetCurrent() - t0
                LaunchProfiler.endPhase("ModelContainerCreation", signpostState)
                Names_3App.launchLogger.info("🚀 [Launch] ModelContainer (local fallback) created in \(String(format: "%.3f", elapsed))s")
                return container
            } catch {
                LaunchProfiler.endPhase("ModelContainerCreation", signpostState)
                fatalError("Could not create local fallback ModelContainer: \(error)")
            }
        }
    }()

    /// One-time UUID migration. Not used in the main path — UUID migration runs in AppLaunchCoordinator (off main).
    /// Kept for tests or legacy callers that may invoke it explicitly.
    @MainActor
    private static func ensureUniqueUUIDs(in container: ModelContainer) {
        let t0 = CFAbsoluteTimeGetCurrent()
        let signpostState = LaunchProfiler.beginPhase("EnsureUniqueUUIDs")
        launchLogger.info("🚀 [Launch] ensureUniqueUUIDs started (\(LaunchProfiler.mainThreadTag))")
        if UserDefaults.standard.bool(forKey: UUIDMigrationService.defaultsKey) {
            LaunchProfiler.endPhase("EnsureUniqueUUIDs", signpostState)
            launchLogger.info("🚀 [Launch] ensureUniqueUUIDs skipped (already done)")
            return
        }
        let context = ModelContext(container)
        let anyFixed = UUIDMigrationService.runMigration(context: context)
        if anyFixed {
            UserDefaults.standard.set(true, forKey: UUIDMigrationService.defaultsKey)
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        LaunchProfiler.endPhase("EnsureUniqueUUIDs", signpostState)
        launchLogger.info("🚀 [Launch] ensureUniqueUUIDs completed in \(String(format: "%.3f", elapsed))s, anyFixed=\(anyFixed)")
    }

    var body: some Scene {
        Self.launchLogger.info("🚀 [Launch] App.body evaluated")
        return WindowGroup {
            LaunchRootView(
                modelContainer: sharedModelContainer,
                appDelegate: appDelegate
            )
            .environment(\.connectivityMonitor, ConnectivityMonitor.shared)
            .environment(\.cloudKitMirroringResetCoordinator, CloudKitMirroringResetCoordinator.shared)
            .environment(\.storageMonitor, StorageMonitor.shared)
            .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Ensure window receives touches on device (fixes unresponsive tap on physical device).
                if let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow }) ?? UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first {
                    window.makeKeyAndVisible()
                }
                // Run post-launch immediately when scene is active (user-initiated priority).
                Task(priority: .userInitiated) { @MainActor in
                    await AppLaunchCoordinator.shared.runPostLaunchPhases(
                        modelContainer: sharedModelContainer,
                        appDelegate: appDelegate
                    )
                }
                StorageMonitor.shared.refreshIfNeeded()
                QuizReminderService.shared.ensureScheduledIfEnabledAndAuthorized()
            }
        }
    }
}