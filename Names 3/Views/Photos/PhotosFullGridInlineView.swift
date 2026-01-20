import SwiftUI
import SwiftData
import Photos

struct PhotosFullGridInlineView: View {
    let scope: PhotosPickerScope
    let contactsContext: ModelContext
    let initialScrollDate: Date?
    @Binding var faceDetectionViewModel: FaceDetectionViewModel?
    let onPhotoPicked: (UIImage, Date?) -> Void
    let onDismiss: () -> Void
    let attemptQuickAssign: ((UIImage, Date?) async -> Bool)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            PhotosDayPickerView(
                scope: scope,
                contactsContext: contactsContext,
                initialScrollDate: initialScrollDate,
                presentationMode: .detailView,
                faceDetectionViewModel: $faceDetectionViewModel,
                onPick: { image, date in
                    onPhotoPicked(image, date)
                },
                attemptQuickAssign: attemptQuickAssign,
                onDismiss: onDismiss
            )
        }
        .background(Color(UIColor.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.15), radius: 30, x: 0, y: 10)
        .ignoresSafeArea(edges: .bottom)
    }
}