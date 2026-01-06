import SwiftUI
import SwiftData
import Photos
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names", category: "PhotosInlineView")

struct PhotosInlineView: View {
    @Environment(\.modelContext) private var modelContext
    let contactsContext: ModelContext
    let onPhotoPicked: (UIImage, Date?) -> Void
    let isVisible: Bool
    
    init(contactsContext: ModelContext, isVisible: Bool = true, onPhotoPicked: @escaping (UIImage, Date?) -> Void) {
        self.contactsContext = contactsContext
        self.isVisible = isVisible
        self.onPhotoPicked = onPhotoPicked
        logger.info("PhotosInlineView init")
    }
    
    var body: some View {
        PhotosGridViewControllerRepresentable(
            isVisible: isVisible,
            onPhotoPicked: onPhotoPicked
        )
        .background(Color(UIColor.systemGroupedBackground))
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - UIViewControllerRepresentable

struct PhotosGridViewControllerRepresentable: UIViewControllerRepresentable {
    let isVisible: Bool
    let onPhotoPicked: (UIImage, Date?) -> Void
    
    func makeUIViewController(context: Context) -> PhotosGridViewController {
        logger.info("PhotosGridViewControllerRepresentable makeUIViewController")
        let controller = PhotosGridViewController()
        controller.onPhotoPicked = onPhotoPicked
        return controller
    }
    
    func updateUIViewController(_ uiViewController: PhotosGridViewController, context: Context) {
        logger.debug("PhotosGridViewControllerRepresentable updateUIViewController isVisible=\(self.isVisible)")
        uiViewController.onPhotoPicked = onPhotoPicked
    }
}