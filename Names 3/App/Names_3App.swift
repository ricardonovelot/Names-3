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

@main
struct Names_3App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    /// `nil` until the ModelContainer is ready and post-launch services have started.
    /// Setting this triggers the main UI to appear.
    @State private var modelContainer: ModelContainer?

    /// Bootstraps PhaseGate for Video Feed (AVAudioSession, MediaPlayer guards).
    private let feedLifecycleMonitor = AppLifecycleMonitor()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "SwiftData")
    private static let launchLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "Launch")

    private static let appSchema = Schema([
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
        JournalEntry.self,
    ])

    init() {
        LaunchProfiler.markProcessStart()
        Self.launchLogger.info("🚀 [Launch] [+\(LaunchProfiler.elapsedSinceProcessStart())s] App init (\(LaunchProfiler.mainThreadTag))")
    }

    // MARK: - ModelContainer

    /// How long to wait for CloudKit to initialize before falling back to local-only.
    private static let cloudKitTimeoutSeconds: Double = 25

    /// Creates the ModelContainer off the main thread.
    ///
    /// Strategy: race CloudKit initialization against a 25-second timeout.
    /// - If CloudKit succeeds: use it (syncs with iCloud).
    /// - If CloudKit is slow (>25s): use same on-disk store without sync so data is preserved.
    /// - If CloudKit fails immediately (returns nil): cancel the timeout immediately — do NOT
    ///   wait the full 25 seconds — and open the local store right away.
    /// - Ultimate fallback: a separate local store if both above fail.
    private static func createModelContainer() async -> ModelContainer {
        let t0 = CFAbsoluteTimeGetCurrent()
        let signpostState = LaunchProfiler.beginPhase("ModelContainerCreation")
        launchLogger.info("🚀 [Launch] ModelContainer creation started (background)")

        let schema = appSchema
        let cloudConfig = ModelConfiguration(
            "default",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.com.ricardo.Names4")
        )
        // Uses the same on-disk store as "default" but disables CloudKit sync.
        // Preserves user data when CloudKit is unavailable.
        let localConfigSameStore = ModelConfiguration(
            "default",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        let localConfigFallback = ModelConfiguration(
            "local-fallback",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        // THE CORE RACE — read this carefully before changing it.
        //
        // Problem with running ModelContainer(...) directly inside a TaskGroup child task:
        //   ModelContainer(for:configurations:) is a *synchronous* Objective-C initializer.
        //   It does not cooperate with Swift's cooperative cancellation model.
        //   withTaskGroup MUST wait for ALL child tasks before it can return — even cancelled ones.
        //   So if the 25s timeout fires and we call group.cancelAll(), the group is still stuck
        //   waiting for the synchronous CloudKit init call to return, which can take 60–120+ seconds
        //   on a slow or flaky iCloud connection. The splash screen freezes the entire time.
        //
        // Fix: run the blocking ModelContainer(...) call in a Task.detached OUTSIDE the group.
        //   Inside the group, only `try? await cloudKitTask.value` — which IS a cooperative
        //   Swift suspension point. When a group child task is cancelled (via cancelAll()),
        //   Swift's runtime injects CancellationError at the suspension point immediately.
        //   The `try?` converts it to nil, the child task exits, and withTaskGroup returns
        //   in milliseconds. The underlying detached task continues in background (abandoned) —
        //   we simply stop waiting for it.
        //
        // Race outcomes:
        //   • CloudKit succeeds first  → non-nil from group → cancelAll() kills timeout sleep
        //   • CloudKit fails fast (nil) → nil from group → cancelAll() kills timeout sleep
        //                                  → immediate local creation in the fallback below
        //   • Timeout fires (25s)       → non-nil localConfigSameStore → cancelAll() interrupts
        //                                  `await cloudKitTask.value` at its suspension point
        //                                  → withTaskGroup exits in < 1ms after the 25s
        let cloudKitTask = Task.detached(priority: .userInitiated) {
            try? ModelContainer(for: schema, configurations: [cloudConfig])
        }

        let raceResult: ModelContainer? = await withTaskGroup(of: ModelContainer?.self) { group in
            // Wraps the detached task in a group task. The `await` is a suspension point:
            // cancellation interrupts it immediately without waiting for the blocking init call.
            group.addTask(priority: .userInitiated) {
                try? await cloudKitTask.value
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(cloudKitTimeoutSeconds))
                return try? ModelContainer(for: schema, configurations: [localConfigSameStore])
            }

            // First non-nil result wins. cancelAll() is always safe here because both
            // the `await cloudKitTask.value` and `Task.sleep` are cooperative suspension points.
            guard let first = await group.next() else { return nil }
            if let container = first {
                group.cancelAll()
                return container
            }
            group.cancelAll()
            return nil
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        LaunchProfiler.endPhase("ModelContainerCreation", signpostState)

        if let container = raceResult {
            let strategy = elapsed < cloudKitTimeoutSeconds + 2 ? "CloudKit" : "local-same-store"
            launchLogger.info("🚀 [Launch] ModelContainer (\(strategy)) ready in \(String(format: "%.3f", elapsed))s")
            return container
        }

        // CloudKit failed fast — create local container immediately (no extra wait).
        launchLogger.info("🚀 [Launch] CloudKit failed; creating local container (elapsed: \(String(format: "%.3f", elapsed))s)")
        if let local = try? ModelContainer(for: schema, configurations: [localConfigSameStore]) {
            return local
        }

        logger.warning("Local same-store also failed. Using local-fallback.")
        do {
            return try ModelContainer(for: schema, configurations: [localConfigFallback])
        } catch {
            fatalError("Could not create ModelContainer with any configuration: \(error)")
        }
    }

    // MARK: - Scene

    var body: some Scene {
        Self.launchLogger.info("🚀 [Launch] App.body evaluated")
        return WindowGroup {
            Group {
                if let container = modelContainer {
                    // Services are already started by the time this branch is reached.
                    // Environments injected once here; they propagate automatically to all descendants.
                    LaunchRootView(modelContainer: container, appDelegate: appDelegate)
                        .environment(\.connectivityMonitor, ConnectivityMonitor.shared)
                        .environment(\.cloudKitMirroringResetCoordinator, CloudKitMirroringResetCoordinator.shared)
                        .environment(\.storageMonitor, StorageMonitor.shared)
                        .modelContainer(container)
                } else {
                    // Minimal splash while ModelContainer is being created and services started.
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView()
                                .scaleEffect(1.1)
                                .tint(.white)
                        }
                }
            }
            .preferredColorScheme(.dark)
            .task {
                guard modelContainer == nil else { return }

                // Step 1: create the persistent store off the main thread.
                let container = await Task.detached(priority: .userInitiated) {
                    await Self.createModelContainer()
                }.value

                // Step 2: start all post-launch services before revealing any UI.
                // Single canonical call site — no need for a backup in the scenePhase handler.
                await AppLaunchCoordinator.shared.runPostLaunchPhases(
                    modelContainer: container,
                    appDelegate: appDelegate
                )

                // Step 3: publish the container — this flips the gate and shows LaunchRootView.
                modelContainer = container
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            // Restore key-window status after UIKit modals (e.g. WelcomeFaceNamingViewController)
            // are dismissed; without this, taps can be swallowed on physical devices.
            restoreKeyWindowIfNeeded()

            // Per-foreground refresh — these are safe to call repeatedly.
            StorageMonitor.shared.refreshIfNeeded()
            QuizReminderService.shared.ensureScheduledIfEnabledAndAuthorized()
        }
    }

    // MARK: - Helpers

    /// Finds the active window and calls `makeKeyAndVisible` to restore touch delivery after
    /// UIKit modal presentations outside of SwiftUI's managed hierarchy.
    private func restoreKeyWindowIfNeeded() {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let targetScene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first
        guard let windowScene = targetScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
                ?? windowScene.windows.first else { return }
        window.makeKeyAndVisible()
    }
}
