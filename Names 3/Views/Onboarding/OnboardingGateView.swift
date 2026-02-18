//
//  OnboardingGateView.swift
//  Names 3
//
//  Shown on first launch instead of ContentView. Presents onboarding as soon as the
//  window is available so the user never sees an empty feed for minutes while CloudKit
//  syncs or while Phase 3 is delayed by main-queue backlog.
//

import SwiftUI
import SwiftData
import UIKit

/// Minimal root shown when onboarding has not been completed. Presents onboarding
/// immediately when the view appears so the flow is: gate → onboarding → ContentView.
struct OnboardingGateView: View {
    let modelContainer: ModelContainer
    let appDelegate: AppDelegate

    @State private var hasPresentedOnboarding = false
    @State private var retryCount = 0
    private let maxWindowRetries = 5

    var body: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
            .onAppear {
                presentOnboardingIfNeeded()
            }
    }

    private func presentOnboardingIfNeeded() {
        guard !hasPresentedOnboarding else { return }

        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
              ?? windowScene.windows.first else {
            guard retryCount < maxWindowRetries else { return }
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                presentOnboardingIfNeeded()
            }
            return
        }

        hasPresentedOnboarding = true
        let modelContext = ModelContext(modelContainer)
        OnboardingCoordinatorManager.shared.showOnboarding(
            in: window,
            forced: false,
            modelContext: modelContext
        )
    }
}
