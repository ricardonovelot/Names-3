import UIKit

final class PhotoZoomTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    
    private let isPresenting: Bool
    private let originFrame: CGRect
    private let originImage: UIImage?
    
    init(isPresenting: Bool, originFrame: CGRect, originImage: UIImage?) {
        self.isPresenting = isPresenting
        self.originFrame = originFrame
        self.originImage = originImage
        super.init()
    }
    
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.35
    }
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromVC = transitionContext.viewController(forKey: .from),
              let toVC = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }
        
        let containerView = transitionContext.containerView
        
        if isPresenting {
            animatePresentation(from: fromVC, to: toVC, in: containerView, context: transitionContext)
        } else {
            animateDismissal(from: fromVC, to: toVC, in: containerView, context: transitionContext)
        }
    }
    
    private func animatePresentation(from: UIViewController, to: UIViewController, in container: UIView, context: UIViewControllerContextTransitioning) {
        guard let detailVC = to as? PhotoDetailViewController else {
            context.completeTransition(false)
            return
        }
        
        let snapshotImageView = UIImageView(image: originImage)
        snapshotImageView.contentMode = .scaleAspectFill
        snapshotImageView.clipsToBounds = true
        snapshotImageView.frame = originFrame
        
        to.view.frame = context.finalFrame(for: to)
        to.view.alpha = 0
        to.view.layoutIfNeeded()
        
        container.addSubview(to.view)
        container.addSubview(snapshotImageView)
        
        detailVC.imageView.isHidden = true
        
        let finalFrame = container.convert(detailVC.imageView.bounds, from: detailVC.imageView)
        
        UIView.animate(
            withDuration: transitionDuration(using: context),
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.2,
            options: [.curveEaseInOut]
        ) {
            snapshotImageView.frame = finalFrame
            snapshotImageView.contentMode = .scaleAspectFit
            to.view.alpha = 1.0
        } completion: { _ in
            snapshotImageView.removeFromSuperview()
            detailVC.imageView.isHidden = false
            context.completeTransition(!context.transitionWasCancelled)
        }
    }
    
    private func animateDismissal(from: UIViewController, to: UIViewController, in container: UIView, context: UIViewControllerContextTransitioning) {
        guard let detailVC = from as? PhotoDetailViewController else {
            context.completeTransition(false)
            return
        }
        
        let snapshotImageView = UIImageView(image: detailVC.imageView.image)
        snapshotImageView.contentMode = .scaleAspectFit
        snapshotImageView.clipsToBounds = true
        snapshotImageView.frame = container.convert(detailVC.imageView.bounds, from: detailVC.imageView)
        
        to.view.frame = context.finalFrame(for: to)
        
        container.insertSubview(to.view, at: 0)
        container.addSubview(snapshotImageView)
        
        detailVC.imageView.isHidden = true
        
        UIView.animate(
            withDuration: transitionDuration(using: context),
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.2,
            options: [.curveEaseInOut]
        ) {
            snapshotImageView.frame = self.originFrame
            snapshotImageView.contentMode = .scaleAspectFill
            from.view.alpha = 0
        } completion: { _ in
            snapshotImageView.removeFromSuperview()
            detailVC.imageView.isHidden = false
            context.completeTransition(!context.transitionWasCancelled)
        }
    }
}