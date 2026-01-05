import UIKit

final class PhotoPanInteractor: NSObject {
    
    // MARK: - Properties
    
    private(set) var isInteractive = false
    private weak var viewController: PhotoDetailViewController?
    private var animator: UIViewPropertyAnimator?
    private var context: UIViewControllerContextTransitioning?
    
    // Track the initial state for smooth interaction
    private var initialTranslation: CGFloat = 0
    private var shouldCompleteTransition = false
    
    // MARK: - Initialization
    
    init(viewController: PhotoDetailViewController) {
        self.viewController = viewController
        super.init()
        setupPanGesture()
    }
    
    // MARK: - Setup
    
    private func setupPanGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        viewController?.view.addGestureRecognizer(pan)
    }
    
    // MARK: - Pan Gesture Handler
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let vc = viewController,
              let view = vc.view,
              let superview = view.superview ?? view.window else { return }
        
        let translation = gesture.translation(in: superview)
        let velocity = gesture.velocity(in: superview)
        let percent = translation.y / superview.bounds.height
        let progress = max(0, min(1, percent))
        
        switch gesture.state {
        case .began:
            isInteractive = true
            initialTranslation = 0
            vc.dismiss(animated: true)
            
        case .changed:
            // Update the animator's progress
            animator?.fractionComplete = progress
            
            // Determine if we should complete based on progress and velocity
            shouldCompleteTransition = progress > 0.3 || velocity.y > 800
            
        case .ended, .cancelled:
            isInteractive = false
            
            // Finish or reverse based on progress and velocity
            if shouldCompleteTransition {
                // Complete the dismissal
                animator?.isReversed = false
                
                // Calculate remaining duration based on velocity
                let remainingDistance = 1.0 - progress
                let springVelocity = velocity.y / superview.bounds.height
                
                // Continue animation with spring physics
                let timing = UISpringTimingParameters(
                    dampingRatio: 0.85,
                    initialVelocity: CGVector(dx: 0, dy: springVelocity)
                )
                animator?.continueAnimation(withTimingParameters: timing, durationFactor: remainingDistance)
            } else {
                // Cancel and spring back
                animator?.isReversed = true
                
                // Spring back with velocity
                let springVelocity = -velocity.y / superview.bounds.height
                let timing = UISpringTimingParameters(
                    dampingRatio: 0.85,
                    initialVelocity: CGVector(dx: 0, dy: springVelocity)
                )
                animator?.continueAnimation(withTimingParameters: timing, durationFactor: progress)
            }
            
        default:
            break
        }
    }
    
    // MARK: - Animator Setup
    
    func wire(to animator: UIViewPropertyAnimator, context: UIViewControllerContextTransitioning) {
        self.animator = animator
        self.context = context
        
        // Pause the animator immediately so we can control it manually
        animator.pauseAnimation()
    }
}

// MARK: - UIViewControllerInteractiveTransitioning

extension PhotoPanInteractor: UIViewControllerInteractiveTransitioning {
    
    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        // The animator is already set up by the transition delegate
        // We just need to store the context
        context = transitionContext
    }
}

// MARK: - UIGestureRecognizerDelegate

extension PhotoPanInteractor: UIGestureRecognizerDelegate {
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              let vc = viewController else {
            return false
        }
        
        // Only allow vertical pan gestures
        let velocity = pan.velocity(in: vc.view)
        let isVertical = abs(velocity.y) > abs(velocity.x)
        
        // Only allow when scrolled to top (so user can scroll content first)
        let atTop: Bool
        if let scrollView = vc.view.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
            atTop = scrollView.contentOffset.y <= -scrollView.contentInset.top
        } else {
            atTop = true
        }
        
        // Only allow downward pan
        return isVertical && atTop && velocity.y > 0
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, 
                          shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't recognize simultaneously with scroll view gestures
        return false
    }
}