import UIKit

final class OnboardingCoordinatorManager {
    static let shared = OnboardingCoordinatorManager()
    
    private var activeCoordinator: OnboardingCoordinator?
    
    private init() {}
    
    func showOnboarding(in window: UIWindow, forced: Bool = false) {
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
        
        coordinator.start { [weak self] in
            print("✅ [CoordinatorManager] Onboarding completed, clearing coordinator")
            self?.activeCoordinator = nil
        }
    }
    
    func dismissOnboarding() {
        print("🔵 [CoordinatorManager] dismissOnboarding called")
        activeCoordinator?.dismiss()
        activeCoordinator = nil
    }
}