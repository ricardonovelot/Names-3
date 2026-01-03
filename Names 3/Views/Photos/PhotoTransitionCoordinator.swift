import UIKit

final class PhotoTransitionCoordinator: NSObject, UIViewControllerTransitioningDelegate {
    
    private let originFrame: CGRect
    private let originImage: UIImage?
    private var interactiveDismiss: InteractiveDismissController?
    
    init(originFrame: CGRect, originImage: UIImage?) {
        self.originFrame = originFrame
        self.originImage = originImage
        super.init()
    }
    
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return PhotoZoomTransitionAnimator(
            isPresenting: true,
            originFrame: originFrame,
            originImage: originImage
        )
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let animator = PhotoZoomTransitionAnimator(
            isPresenting: false,
            originFrame: originFrame,
            originImage: originImage
        )
        
        if let interactive = interactiveDismiss {
            return animator
        }
        
        return animator
    }
    
    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return interactiveDismiss
    }
    
    func startInteractiveDismiss() {
        let animator = PhotoZoomTransitionAnimator(
            isPresenting: false,
            originFrame: originFrame,
            originImage: originImage
        )
        interactiveDismiss = InteractiveDismissController(animator: animator)
    }
    
    func updateInteractiveDismiss(with gesture: UIPanGestureRecognizer) {
        interactiveDismiss?.handlePan(gesture)
    }
}