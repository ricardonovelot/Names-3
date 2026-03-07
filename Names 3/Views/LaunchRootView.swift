//
//  LaunchRootView.swift
//  Names 3
//
//  Root view shown after the ModelContainer and post-launch services are ready.
//  By the time this view appears, AppLaunchCoordinator has already run Phase 1+2,
//  so all services (ConnectivityMonitor, StorageMonitor, etc.) are live.
//
//  View hierarchy:
//    Names_3App → LaunchRootView → LaunchGateView → ContentView   (returning user)
//    Names_3App → LaunchRootView → OnboardingGateView             (new user)
//
//  Environment values (connectivityMonitor, storageMonitor, modelContainer, etc.)
//  are injected once in Names_3App and propagate automatically — no re-injection needed here.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - UserDefaults Keys

private enum LaunchKeys {
    static let hasCompletedOnboarding = "Names3.hasCompletedOnboarding"
    static let onboardingVersion = "Names3.onboardingVersion"
    static let hasShownSyncTransition = "Names3.hasShownSyncTransition"
    static let currentOnboardingVersion = 1
}

// MARK: - LaunchGateView

/// Shown for returning users. Displays a brief sync splash on the very first post-onboarding
/// launch, then shows ContentView. Services are already running when this view appears.
private struct LaunchGateView: View {
    let modelContainer: ModelContainer
    let isFirstLaunchAfterOnboarding: Bool

    @State private var showContentView = false
    @Binding var hasShownSyncTransition: Bool

    /// AppSettings is owned here (app-scoped once main UI is shown) and flows to ContentView
    /// and all its descendants via environmentObject propagation.
    @StateObject private var feedAppSettings = AppSettings()

    var body: some View {
        Group {
            if showContentView {
                ContentView(containerForAsyncLoad: modelContainer)
                    .environmentObject(feedAppSettings)
                    .reportFirstFrame()
            } else {
                splashView
            }
        }
        .task {
            // Services are already started by the time this view appears.
            // Just handle the first-launch sync splash delay.
            if isFirstLaunchAfterOnboarding {
                try? await Task.sleep(for: .milliseconds(300))
            }
            hasShownSyncTransition = true
            showContentView = true
        }
    }

    @ViewBuilder
    private var splashView: some View {
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

// MARK: - LaunchRootView

/// Routes to the main app or onboarding based on completion state.
/// All environments and modelContainer flow from Names_3App — do not re-inject here.
struct LaunchRootView: View {
    let modelContainer: ModelContainer
    let appDelegate: AppDelegate

    @AppStorage(LaunchKeys.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @AppStorage(LaunchKeys.onboardingVersion) private var onboardingVersion = 0
    @AppStorage(LaunchKeys.hasShownSyncTransition) private var hasShownSyncTransition = false

    private var showMainApp: Bool {
        hasCompletedOnboarding && onboardingVersion >= LaunchKeys.currentOnboardingVersion
    }

    var body: some View {
        Group {
            if showMainApp {
                LaunchGateView(
                    modelContainer: modelContainer,
                    isFirstLaunchAfterOnboarding: !hasShownSyncTransition,
                    hasShownSyncTransition: $hasShownSyncTransition
                )
            } else {
                OnboardingGateView(modelContainer: modelContainer, appDelegate: appDelegate)
            }
        }
        .onAppear {
            LaunchProfiler.logCheckpoint("LaunchRootView: showing \(showMainApp ? "LaunchGate" : "OnboardingGate")")
        }
    }
}

// MARK: - Preview

#Preview {
    let container = try! ModelContainer(
        for: Contact.self, Note.self, Tag.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    LaunchRootView(modelContainer: container, appDelegate: AppDelegate())
        .environment(\.connectivityMonitor, ConnectivityMonitor.shared)
        .environment(\.storageMonitor, StorageMonitor.shared)
        .modelContainer(container)
}
