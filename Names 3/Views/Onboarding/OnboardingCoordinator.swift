import UIKit
import SwiftUI

final class OnboardingCoordinator {
    private weak var window: UIWindow?
    private var onboardingViewController: OnboardingViewController?
    private var completion: (() -> Void)?
    
    init(window: UIWindow?) {
        self.window = window
        print("🟢 [Coordinator] Initialized")
    }
    
    deinit {
        print("🔴 [Coordinator] Deinitialized")
    }
    
    func start(completion: (() -> Void)? = nil) {
        self.completion = completion
        print("🟢 [Coordinator] start() called")
        
        let onboardingVC = OnboardingViewController()
        onboardingVC.delegate = self
        onboardingVC.modalPresentationStyle = .fullScreen
        onboardingVC.modalTransitionStyle = .crossDissolve
        self.onboardingViewController = onboardingVC
        
        DispatchQueue.main.async { [weak self] in
            self?.performPresentation(onboardingVC)
        }
    }
    
    func dismiss() {
        print("🔵 [Coordinator] dismiss() called")
        onboardingViewController?.dismiss(animated: true) { [weak self] in
            print("✅ [Coordinator] Dismiss completed")
            self?.onboardingViewController = nil
            OnboardingManager.shared.completeOnboarding()
            self?.completion?()
            self?.completion = nil
        }
    }
    
    private func performPresentation(_ onboardingVC: OnboardingViewController) {
        guard let window = self.window else {
            print("❌ [Coordinator] No window available")
            completion?()
            completion = nil
            return
        }
        
        print("🔍 [Coordinator] Finding presenter...")
        
        guard let rootVC = window.rootViewController else {
            print("❌ [Coordinator] No root view controller")
            completion?()
            completion = nil
            return
        }
        
        let presenter = findTopMostViewController(rootVC)
        print("✅ [Coordinator] Found presenter: \(type(of: presenter))")
        print("   Is presenting: \(presenter.presentedViewController != nil)")
        print("   Can present: \(presenter.view.window != nil)")
        
        if presenter.presentedViewController != nil {
            print("⚠️ [Coordinator] Presenter is already presenting something, waiting...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self else { return }
                self.performPresentation(onboardingVC)
            }
            return
        }
        
        print("🚀 [Coordinator] Presenting onboarding...")
        presenter.present(onboardingVC, animated: true) {
            print("✅ [Coordinator] Presentation animation completed")
        }
    }
    
    private func findTopMostViewController(_ controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return findTopMostViewController(presented)
        }
        
        if let nav = controller as? UINavigationController,
           let visible = nav.visibleViewController {
            return findTopMostViewController(visible)
        }
        
        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController {
            return findTopMostViewController(selected)
        }
        
        return controller
    }
}

extension OnboardingCoordinator: OnboardingViewControllerDelegate {
    func onboardingViewControllerDidFinish(_ controller: OnboardingViewController) {
        print("✅ [Coordinator] Onboarding finished delegate called")
        dismiss()
    }
}