//
//  LaunchRootView.swift
//  Names 3
//
//  Root that shows the main feed immediately. Post-launch phases run in the background
//  using Swift Concurrency, without gating ContentView’s first paint.
//

import SwiftUI
import SwiftData
import UIKit

private let hasCompletedOnboardingKey = "Names3.hasCompletedOnboarding"
private let onboardingVersionKey = "Names3.onboardingVersion"
private let currentOnboardingVersion = 1
private let hasShownSyncTransitionKey = "Names3.hasShownSyncTransition"

/// Minimal gate: NO @Query, so main thread stays free. Runs post-launch FIRST, then ContentView.
/// Critical: ContentView's @Query blocks 100s+ during CloudKit sync; this gate lets post-launch
/// and scenePhase run before the heavy fetch.
private struct LaunchGateView: View {
    let modelContainer: ModelContainer
    let appDelegate: AppDelegate
    let isFirstLaunchAfterOnboarding: Bool
    @State private var showContentView = false
    @Binding var hasShownSyncTransition: Bool
    @StateObject private var feedAppSettings = AppSettings()

    var body: some View {
        Group {
            if showContentView {
                ContentView(containerForAsyncLoad: modelContainer)
                    .modelContainer(modelContainer)
                    .environment(\.connectivityMonitor, ConnectivityMonitor.shared)
                    .environment(\.cloudKitMirroringResetCoordinator, CloudKitMirroringResetCoordinator.shared)
                    .environment(\.storageMonitor, StorageMonitor.shared)
                    .environmentObject(feedAppSettings)
                    .reportFirstFrame()
            } else {
                ZStack {
                    Color(uiColor: .systemGroupedBackground)
                        .ignoresSafeArea()
                    if isFirstLaunchAfterOnboarding {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.1)
                                .tint(.white)
                            Text("Syncing…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task {
            await AppLaunchCoordinator.shared.runPostLaunchPhases(
                modelContainer: modelContainer,
                appDelegate: appDelegate
            )
            if isFirstLaunchAfterOnboarding {
                try? await Task.sleep(for: .milliseconds(300))
            }
            hasShownSyncTransition = true
            showContentView = true
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
                LaunchGateView(
                    modelContainer: modelContainer,
                    appDelegate: appDelegate,
                    isFirstLaunchAfterOnboarding: !hasShownSyncTransition,
                    hasShownSyncTransition: $hasShownSyncTransition
                )
                .environment(\.connectivityMonitor, ConnectivityMonitor.shared)
                .environment(\.cloudKitMirroringResetCoordinator, CloudKitMirroringResetCoordinator.shared)
                .environment(\.storageMonitor, StorageMonitor.shared)
            } else {
                OnboardingGateView(modelContainer: modelContainer, appDelegate: appDelegate)
                    .modelContainer(modelContainer)
                    .environment(\.connectivityMonitor, ConnectivityMonitor.shared)
                    .environment(\.cloudKitMirroringResetCoordinator, CloudKitMirroringResetCoordinator.shared)
                    .environment(\.storageMonitor, StorageMonitor.shared)
            }
        }
        .onAppear {
            LaunchProfiler.logCheckpoint("LaunchRootView: showing \(showMainApp ? "LaunchGate" : "OnboardingGate")")
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
