import UIKit

final class PhotoZoomTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    
    // MARK: - Properties
    
    private let isPresenting: Bool
    private let originFrame: CGRect
    private let originImage: UIImage?
    private let duration: TimeInterval = 0.45
    
    // Expose the animator so the interactive controller can control it
    private(set) var propertyAnimator: UIViewPropertyAnimator?
    
    var onDismissComplete: (() -> Void)?
    private var hasCalledCompletion = false
    
    // MARK: - Initialization
    
    init(isPresenting: Bool, originFrame: CGRect, originImage: UIImage?) {
        self.isPresenting = isPresenting
        self.originFrame = originFrame
        self.originImage = originImage
        super.init()
    }
    
    // MARK: - UIViewControllerAnimatedTransitioning
    
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return duration
    }
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        // Create the animator
        let animator = interruptibleAnimator(using: transitionContext)
        
        // Start it immediately (interactive transitions will pause it)
        animator.startAnimation()
    }
    
    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        // Return existing animator if already created for this transition
        if let propertyAnimator = propertyAnimator {
            return propertyAnimator
        }
        
        print("🔵 [PhotoZoomAnimator] Creating new animator - isPresenting: \(isPresenting)")
        
        guard let fromVC = transitionContext.viewController(forKey: .from),
              let toVC = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return UIViewPropertyAnimator(duration: 0, curve: .linear)
        }
        
        let containerView = transitionContext.containerView
        
        if isPresenting {
            propertyAnimator = createPresentationAnimator(
                from: fromVC,
                to: toVC,
                in: containerView,
                context: transitionContext
            )
        } else {
            propertyAnimator = createDismissalAnimator(
                from: fromVC,
                to: toVC,
                in: containerView,
                context: transitionContext
            )
        }
        
        return propertyAnimator!
    }
    
    // MARK: - Presentation Animation
    
    private func createPresentationAnimator(
        from: UIViewController,
        to: UIViewController,
        in container: UIView,
        context: UIViewControllerContextTransitioning
    ) -> UIViewPropertyAnimator {
        
        guard let detailVC = to as? PhotoDetailViewController else {
            context.completeTransition(false)
            return UIViewPropertyAnimator(duration: 0, curve: .linear)
        }
        
        // Create snapshot for the transition
        let snapshotImageView = UIImageView(image: originImage ?? detailVC.imageView.image)
        snapshotImageView.contentMode = .scaleAspectFill
        snapshotImageView.clipsToBounds = true
        snapshotImageView.frame = originFrame
        snapshotImageView.layer.cornerRadius = 0
        
        // Setup destination view
        to.view.frame = context.finalFrame(for: to)
        to.view.alpha = 0
        to.view.layoutIfNeeded()
        
        // Add views to container
        container.addSubview(to.view)
        container.addSubview(snapshotImageView)
        
        // Hide the actual image view during transition
        detailVC.imageView.alpha = 0
        
        // Calculate final frame
        let finalFrame = container.convert(detailVC.imageView.bounds, from: detailVC.imageView)
        
        // Create the property animator with spring physics
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 0.85) {
            snapshotImageView.frame = finalFrame
            snapshotImageView.contentMode = .scaleAspectFit
            to.view.alpha = 1.0
            from.view.alpha = 0.0
        }
        
        animator.addCompletion { [weak self] position in
            let completed = position == .end
            
            snapshotImageView.removeFromSuperview()
            detailVC.imageView.alpha = 1.0
            from.view.alpha = 1.0
            
            context.completeTransition(completed && !context.transitionWasCancelled)
            
            // Reset animator state after transition completes
            self?.propertyAnimator = nil
            self?.hasCalledCompletion = false
        }
        
        return animator
    }
    
    // MARK: - Dismissal Animation
    
    private func createDismissalAnimator(
        from: UIViewController,
        to: UIViewController,
        in container: UIView,
        context: UIViewControllerContextTransitioning
    ) -> UIViewPropertyAnimator {
        
        guard let detailVC = from as? PhotoDetailViewController else {
            context.completeTransition(false)
            return UIViewPropertyAnimator(duration: 0, curve: .linear)
        }
        
        let snapshotImageView = UIImageView(image: detailVC.imageView.image)
        snapshotImageView.contentMode = .scaleAspectFit
        snapshotImageView.clipsToBounds = true
        
        let currentFrame = container.convert(detailVC.imageView.bounds, from: detailVC.imageView)
        snapshotImageView.frame = currentFrame
        
        to.view.frame = context.finalFrame(for: to)
        
        container.insertSubview(to.view, at: 0)
        container.addSubview(snapshotImageView)
        
        detailVC.imageView.alpha = 0
        
        let dimmingView = UIView(frame: container.bounds)
        dimmingView.backgroundColor = .black
        dimmingView.alpha = 1.0
        container.insertSubview(dimmingView, belowSubview: snapshotImageView)
        
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 0.85) {
            snapshotImageView.frame = self.originFrame
            snapshotImageView.contentMode = .scaleAspectFill
            from.view.alpha = 0
            dimmingView.alpha = 0
        }
        
        animator.addCompletion { [weak self] position in
            let completed = position == .end
            
            if completed && !context.transitionWasCancelled && (self?.hasCalledCompletion == false) {
                self?.hasCalledCompletion = true
                print("✅ [PhotoZoomAnimator] Dismissal complete, calling callback")
                self?.onDismissComplete?()
            }
            
            snapshotImageView.removeFromSuperview()
            dimmingView.removeFromSuperview()
            detailVC.imageView.alpha = 1.0
            from.view.alpha = 1.0
            
            context.completeTransition(completed && !context.transitionWasCancelled)
            
            // Reset animator state after transition completes
            self?.propertyAnimator = nil
            self?.hasCalledCompletion = false
        }
        
        return animator
    }
}