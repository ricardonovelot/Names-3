import SwiftUI
import SwiftData

struct PhotoDetailViewWrapper: UIViewControllerRepresentable {
    let image: UIImage
    let date: Date?
    let contactsContext: ModelContext
    let originFrame: CGRect
    let originImage: UIImage?
    let onComplete: (UIImage, Date) -> Void
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> PhotoDetailViewController {
        let vc = PhotoDetailViewController(
            image: image,
            date: date,
            contactsContext: contactsContext,
            onComplete: onComplete
        )
        
        // Set up transition
        let delegate = PhotoZoomTransitionDelegate(
            originFrame: originFrame,
            originImage: originImage
        )
        context.coordinator.transitionDelegate = delegate
        vc.transitioningDelegate = delegate
        vc.modalPresentationStyle = .custom
        
        return vc
    }
    
    func updateUIViewController(_ uiViewController: PhotoDetailViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    class Coordinator {
        let onDismiss: () -> Void
        var transitionDelegate: PhotoZoomTransitionDelegate?
        
        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
    }
}