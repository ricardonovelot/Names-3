import SwiftUI
import SwiftData

struct PhotoDetailViewWrapper: UIViewControllerRepresentable {
    let image: UIImage
    let date: Date?
    let contactsContext: ModelContext
    @Binding var faceDetectionViewModelBinding: FaceDetectionViewModel?
    let onComplete: (UIImage, Date) -> Void
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> PhotoDetailViewController {
        let viewModel = faceDetectionViewModelBinding ?? FaceDetectionViewModel()
        if faceDetectionViewModelBinding == nil {
            faceDetectionViewModelBinding = viewModel
        }
        
        let vc = PhotoDetailViewController(
            image: image,
            date: date,
            contactsContext: contactsContext,
            faceDetectionViewModel: viewModel,
            onComplete: { finalImage, finalDate in
                onComplete(finalImage, finalDate ?? Date())
            }
        )
        
        vc.customBackAction = {
            onDismiss()
        }
        
        return vc
    }
    
    func updateUIViewController(_ uiViewController: PhotoDetailViewController, context: Context) {
    }
}