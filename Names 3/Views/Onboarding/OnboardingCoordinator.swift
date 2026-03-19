import UIKit
import SwiftUI

final class OnboardingCoordinator {
    private weak var window: UIWindow?
    private var onboardingViewController: OnboardingViewController?
    private var completion: (() -> Void)?
    
    init(window: UIWindow?) {
        self.window = window
        DiagnosticsConfig.verbosePrint("🟢 [Coordinator] Initialized")
    }
    
    deinit {
        DiagnosticsConfig.verbosePrint("🔴 [Coordinator] Deinitialized")
    }
    
    func start(completion: (() -> Void)? = nil) {
        self.completion = completion
        DiagnosticsConfig.verbosePrint("🟢 [Coordinator] start() called")
        
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
        DiagnosticsConfig.verbosePrint("🔵 [Coordinator] dismiss() called")
        onboardingViewController?.dismiss(animated: true) { [weak self] in
            DiagnosticsConfig.verbosePrint("✅ [Coordinator] Dismiss completed")
            self?.onboardingViewController = nil
            OnboardingManager.shared.completeOnboarding()
            self?.completion?()
            self?.completion = nil
        }
    }
    
    private func performPresentation(_ onboardingVC: OnboardingViewController) {
        guard let window = self.window else {
            DiagnosticsConfig.verbosePrint("❌ [Coordinator] No window available")
            completion?()
            completion = nil
            return
        }
        
        DiagnosticsConfig.verbosePrint("🔍 [Coordinator] Finding presenter...")
        
        guard let rootVC = window.rootViewController else {
            DiagnosticsConfig.verbosePrint("❌ [Coordinator] No root view controller")
            completion?()
            completion = nil
            return
        }
        
        let presenter = findTopMostViewController(rootVC)
        DiagnosticsConfig.verbosePrint("✅ [Coordinator] Found presenter: \(type(of: presenter))")
        DiagnosticsConfig.verbosePrint("   Is presenting: \(presenter.presentedViewController != nil)")
        DiagnosticsConfig.verbosePrint("   Can present: \(presenter.view.window != nil)")
        
        if presenter.presentedViewController != nil {
            DiagnosticsConfig.verbosePrint("⚠️ [Coordinator] Presenter is already presenting something, waiting...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self = self else { return }
                self.performPresentation(onboardingVC)
            }
            return
        }
        
        DiagnosticsConfig.verbosePrint("🚀 [Coordinator] Presenting onboarding...")
        presenter.present(onboardingVC, animated: true) {
            DiagnosticsConfig.verbosePrint("✅ [Coordinator] Presentation animation completed")
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
        DiagnosticsConfig.verbosePrint("✅ [Coordinator] Onboarding finished delegate called")
        dismiss()
    }
}