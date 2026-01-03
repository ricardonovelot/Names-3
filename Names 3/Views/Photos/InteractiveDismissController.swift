import UIKit

final class InteractiveDismissController: NSObject, UIViewControllerInteractiveTransitioning {
    
    private let animator: PhotoZoomTransitionAnimator
    private var shouldComplete = false
    private var transitionContext: UIViewControllerContextTransitioning?
    
    init(animator: PhotoZoomTransitionAnimator) {
        self.animator = animator
        super.init()
    }
    
    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        self.transitionContext = transitionContext
    }
    
    func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        let translation = gesture.translation(in: view)
        let verticalMovement = translation.y / view.bounds.height
        let progress = max(0.0, min(1.0, verticalMovement))
        
        switch gesture.state {
        case .changed:
            shouldComplete = progress > 0.3
            animator.updateInteractiveProgress(progress)
            
        case .cancelled:
            animator.cancelInteractiveTransition()
            
        case .ended:
            if shouldComplete || gesture.velocity(in: view).y > 1000 {
                animator.finishInteractiveTransition()
            } else {
                animator.cancelInteractiveTransition()
            }
            
        default:
            break
        }
    }
}