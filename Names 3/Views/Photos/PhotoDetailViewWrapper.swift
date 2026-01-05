import SwiftUI
import SwiftData

struct PhotoDetailViewWrapper: View {
    let image: UIImage
    let date: Date?
    let contactsContext: ModelContext
    let onComplete: (UIImage, Date) -> Void
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        PhotoDetailViewWrapperRepresentable(
            image: image,
            date: date,
            contactsContext: contactsContext,
            onComplete: onComplete,
            onDismiss: {
                dismiss()
                onDismiss()
            }
        )
        .ignoresSafeArea()
        .navigationBarHidden(true)
    }
}

private struct PhotoDetailViewWrapperRepresentable: UIViewControllerRepresentable {
    let image: UIImage
    let date: Date?
    let contactsContext: ModelContext
    let onComplete: (UIImage, Date) -> Void
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> PhotoDetailViewControllerHost {
        let host = PhotoDetailViewControllerHost(
            image: image,
            date: date,
            contactsContext: contactsContext,
            onComplete: onComplete,
            onDismiss: onDismiss
        )
        return host
    }
    
    func updateUIViewController(_ uiViewController: PhotoDetailViewControllerHost, context: Context) {
        // No updates needed
    }
}

class PhotoDetailViewControllerHost: UIViewController {
    private let detailVC: PhotoDetailViewController
    private let onDismiss: () -> Void
    
    init(image: UIImage, date: Date?, contactsContext: ModelContext, onComplete: @escaping (UIImage, Date) -> Void, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.detailVC = PhotoDetailViewController(
            image: image,
            date: date,
            contactsContext: contactsContext,
            onComplete: { finalImage, finalDate in
                // Convert Date? to Date by providing current date as fallback
                onComplete(finalImage, finalDate ?? Date())
            }
        )
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        addChild(detailVC)
        view.addSubview(detailVC.view)
        detailVC.view.frame = view.bounds
        detailVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        detailVC.didMove(toParent: self)
        
        // Intercept back button to call onDismiss
        detailVC.customBackAction = { [weak self] in
            self?.onDismiss()
        }
    }
}