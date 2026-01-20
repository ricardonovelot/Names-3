import SwiftUI
import SwiftData

enum PhotosPickerScope: Hashable {
    case day(Date)
    case all
    
    var initialScrollDate: Date? {
        switch self {
        case .day(let date):
            return date
        case .all:
            return nil
        }
    }
}

enum PhotoPickerPresentationMode {
    /// Shows PhotoDetailView for face detection and multi-person naming
    case detailView
    /// Directly calls onPick without showing detail view
    case directSelection
}

struct PhotosDayPickerHost: View {
    let scope: PhotosPickerScope
    let contactsContext: ModelContext
    let onPick: (UIImage, Date?) -> Void
    let initialScrollDate: Date?
    let attemptQuickAssign: ((UIImage, Date?) async -> Bool)?
    @Binding var faceDetectionViewModel: FaceDetectionViewModel?

    init(
        scope: PhotosPickerScope,
        contactsContext: ModelContext,
        initialScrollDate: Date? = nil,
        faceDetectionViewModel: Binding<FaceDetectionViewModel?>,
        onPick: @escaping (UIImage, Date?) -> Void,
        attemptQuickAssign: ((UIImage, Date?) async -> Bool)? = nil
    ) {
        self.scope = scope
        self.contactsContext = contactsContext
        self.initialScrollDate = initialScrollDate ?? scope.initialScrollDate
        self._faceDetectionViewModel = faceDetectionViewModel
        self.onPick = onPick
        self.attemptQuickAssign = attemptQuickAssign
        
        if let scrollDate = self.initialScrollDate {
            print("🔵 [PhotosDayPickerHost] Initialized with scroll date: \(scrollDate)")
        } else {
            print("🔵 [PhotosDayPickerHost] Initialized without scroll date")
        }
        print("🔵 [PhotosDayPickerHost] Scope: \(scope)")
    }

    var body: some View {
        let _ = print("🔵 [PhotosDayPickerHost] body evaluated - scope: \(scope)")
        
        return PhotosDayPickerView(
            scope: scope,
            contactsContext: contactsContext,
            initialScrollDate: initialScrollDate,
            faceDetectionViewModel: $faceDetectionViewModel,
            onPick: onPick,
            attemptQuickAssign: attemptQuickAssign
        )
    }
}