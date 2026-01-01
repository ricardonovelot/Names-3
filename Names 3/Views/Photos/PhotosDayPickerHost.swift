import SwiftUI

enum PhotosPickerScope: Hashable {
    case day(Date)
    case all
}

struct PhotosDayPickerHost: View {
    let scope: PhotosPickerScope
    let onPick: (UIImage, Date?) -> Void

    var body: some View {
        PhotosDayPickerView(scope: scope) { image, date in
            onPick(image, date)
        }
        .id(scope)
    }
}