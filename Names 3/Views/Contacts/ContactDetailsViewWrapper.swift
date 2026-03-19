import SwiftUI
import SwiftData
import os

/// UIViewControllerRepresentable bridge that slots ContactDetailsViewController
/// into any SwiftUI NavigationStack or sheet presentation.
struct ContactDetailsViewWrapper: UIViewControllerRepresentable {
    private static let wrapperLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "Navigation")
    @Bindable var contact: Contact
    let modelContext: ModelContext
    var isCreationFlow: Bool = false
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    var onBack: (() -> Void)?
    var onRequestAddNote: (() -> Void)?
    var highlightedNoteUUID: UUID?

    @StateObject private var photoSelectorCoordinator = ContactPhotoSelectorCoordinator()
    @StateObject private var faceRecognitionCoordinator = FaceRecognitionCoordinator()

    func makeUIViewController(context: Context) -> ContactDetailsViewController {
        // ⚠️ If this fires MORE THAN ONCE for the same navigation position it means SwiftUI
        // discarded the old VC and is creating a new one — a sign of view-identity instability.
        Self.wrapperLogger.debug("⬡ ContactDetailsViewWrapper MAKE — contact=\(contact.displayName) highlighted=\(highlightedNoteUUID?.uuidString ?? "nil")")
        let vc = ContactDetailsViewController(
            contact: contact,
            modelContext: modelContext,
            photoSelectorCoordinator: photoSelectorCoordinator,
            faceRecognitionCoordinator: faceRecognitionCoordinator,
            highlightedNoteUUID: highlightedNoteUUID
        )
        vc.isCreationFlow = isCreationFlow
        vc.onSave = onSave
        vc.onCancel = onCancel
        vc.onBack = onBack
        vc.onRequestAddNote = onRequestAddNote
        return vc
    }

    func updateUIViewController(_ uiViewController: ContactDetailsViewController, context: Context) {
        Self.wrapperLogger.debug("⬡ ContactDetailsViewWrapper UPDATE — contact=\(contact.displayName) highlighted=\(highlightedNoteUUID?.uuidString ?? "nil")")
        uiViewController.highlightedNoteUUID = highlightedNoteUUID
        // Keep every callback current so closures always capture the latest SwiftUI state.
        // Without this, onBack/onRequestAddNote would be frozen to the closures produced on the first render.
        uiViewController.onBack = onBack
        uiViewController.onRequestAddNote = onRequestAddNote
    }
}
