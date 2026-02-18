//
//  LaunchRootView.swift
//  Names 3
//
//  Root that shows the main feed immediately. Post-launch phases run in the background
//  using Swift Concurrency, without gating ContentView’s first paint.
//

import SwiftUI
import SwiftData

private let hasCompletedOnboardingKey = "Names3.hasCompletedOnboarding"
private let onboardingVersionKey = "Names3.onboardingVersion"
private let currentOnboardingVersion = 1
private let hasShownSyncTransitionKey = "Names3.hasShownSyncTransition"

/// Lightweight transition shown after onboarding dismisses (first time only). No @Query—avoids
/// blocking the main thread during CloudKit sync. Yields ~2s before ContentView loads.
private struct SyncTransitionView: View {
    let modelContainer: ModelContainer
    let appDelegate: AppDelegate
    @State private var showContentView = false
    @AppStorage(hasShownSyncTransitionKey) private var hasShownSyncTransition = false

    var body: some View {
        Group {
            if showContentView {
                ContentView()
                    .modelContainer(modelContainer)
                    .environment(\.connectivityMonitor, ConnectivityMonitor.shared)
                    .environment(\.cloudKitMirroringResetCoordinator, CloudKitMirroringResetCoordinator.shared)
                    .environment(\.storageMonitor, StorageMonitor.shared)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    Text("Syncing…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            showContentView = true
            hasShownSyncTransition = true
        }
    }
}

struct LaunchRootView: View {
    let modelContainer: ModelContainer
    let appDelegate: AppDelegate

    @AppStorage(hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @AppStorage(onboardingVersionKey) private var onboardingVersion = 0

    private var showMainApp: Bool {
        hasCompletedOnboarding && onboardingVersion >= currentOnboardingVersion
    }

    @AppStorage(hasShownSyncTransitionKey) private var hasShownSyncTransition = false

    var body: some View {
        Group {
            if showMainApp {
                if hasShownSyncTransition {
                    ContentView()
                        .modelContainer(modelContainer)
                        .environment(\.connectivityMonitor, ConnectivityMonitor.shared)
                        .environment(\.cloudKitMirroringResetCoordinator, CloudKitMirroringResetCoordinator.shared)
                        .environment(\.storageMonitor, StorageMonitor.shared)
                } else {
                    SyncTransitionView(modelContainer: modelContainer, appDelegate: appDelegate)
                        .environment(\.connectivityMonitor, ConnectivityMonitor.shared)
                        .environment(\.cloudKitMirroringResetCoordinator, CloudKitMirroringResetCoordinator.shared)
                        .environment(\.storageMonitor, StorageMonitor.shared)
                }
            } else {
                OnboardingGateView(modelContainer: modelContainer, appDelegate: appDelegate)
                    .modelContainer(modelContainer)
                    .environment(\.connectivityMonitor, ConnectivityMonitor.shared)
                    .environment(\.cloudKitMirroringResetCoordinator, CloudKitMirroringResetCoordinator.shared)
                    .environment(\.storageMonitor, StorageMonitor.shared)
            }
        }
        .task {
            // Post-launch is also triggered from scene .active in Names_3App; this is a fallback
            // if the scene callback didn't run. Coordinator no-ops if already run.
            LaunchProfiler.logCheckpoint("LaunchRootView.task started (non-gating)")
            await AppLaunchCoordinator.shared.runPostLaunchPhases(
                modelContainer: modelContainer,
                appDelegate: appDelegate
            )
            LaunchProfiler.logCheckpoint("LaunchRootView.task completed (post-launch continues in background)")
        }
        .onAppear {
            LaunchProfiler.logCheckpoint("LaunchRootView: showing \(showMainApp ? "ContentView" : "OnboardingGate")")
        }
    }
}

#Preview {
    // Preview with in-memory container for speed
    let container = try! ModelContainer(
        for: Contact.self, Note.self, Tag.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    LaunchRootView(modelContainer: container, appDelegate: AppDelegate())
}
