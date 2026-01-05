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

struct PhotosDayPickerHost: View {
    let scope: PhotosPickerScope
    let contactsContext: ModelContext
    let onPick: (UIImage, Date?) -> Void
    let initialScrollDate: Date?

    init(scope: PhotosPickerScope, contactsContext: ModelContext, initialScrollDate: Date? = nil, onPick: @escaping (UIImage, Date?) -> Void) {
        self.scope = scope
        self.contactsContext = contactsContext
        self.initialScrollDate = initialScrollDate ?? scope.initialScrollDate
        self.onPick = onPick
        
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
            onPick: onPick
        )
    }
}