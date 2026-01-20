import UIKit
import SwiftData

final class OnboardingCoordinatorManager {
    static let shared = OnboardingCoordinatorManager()
    
    private var activeCoordinator: OnboardingCoordinator?
    private var facePromptCoordinator: PostOnboardingFacePromptCoordinator?
    
    private init() {}
    
    func showOnboarding(in window: UIWindow, forced: Bool = false, modelContext: ModelContext? = nil) {
        print("🔵 [CoordinatorManager] showOnboarding called, forced: \(forced)")
        
        if !forced && OnboardingManager.shared.hasCompletedOnboarding {
            print("🔵 [CoordinatorManager] Onboarding already completed, skipping")
            return
        }
        
        if activeCoordinator != nil {
            print("⚠️ [CoordinatorManager] Onboarding already active")
            return
        }
        
        let coordinator = OnboardingCoordinator(window: window)
        self.activeCoordinator = coordinator
        
        coordinator.start { [weak self, weak window] in
            print("✅ [CoordinatorManager] Onboarding completed, clearing coordinator")
            self?.activeCoordinator = nil
            
            guard !forced, let window = window, let modelContext = modelContext else {
                print("🔵 [CoordinatorManager] Skipping face prompt - forced onboarding or missing context")
                return
            }
            
            print("🔵 [CoordinatorManager] Starting post-onboarding face prompt")
            self?.showFaceNamingPrompt(in: window, modelContext: modelContext, forced: false)
        }
    }
    
    func showFaceNamingPrompt(in window: UIWindow, modelContext: ModelContext, forced: Bool = false) {
        print("🔵 [CoordinatorManager] showFaceNamingPrompt called, forced: \(forced)")
        
        guard facePromptCoordinator == nil else {
            print("⚠️ [CoordinatorManager] Face prompt already active")
            return
        }
        
        let coordinator = PostOnboardingFacePromptCoordinator(window: window, modelContext: modelContext)
        self.facePromptCoordinator = coordinator
        
        coordinator.start(forced: forced) { [weak self] in
            print("✅ [CoordinatorManager] Face prompt completed")
            self?.facePromptCoordinator = nil
        }
    }
    
    func dismissOnboarding() {
        print("🔵 [CoordinatorManager] dismissOnboarding called")
        activeCoordinator?.dismiss()
        activeCoordinator = nil
    }
    
    func dismissFacePrompt() {
        print("🔵 [CoordinatorManager] dismissFacePrompt called")
        facePromptCoordinator?.dismiss()
        facePromptCoordinator = nil
    }
}