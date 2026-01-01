import SwiftUI
import SwiftData

struct CustomTagPicker: View {
    @Bindable var contact: Contact

    var body: some View {
        TagPickerView(mode: .contactToggle(contact: contact))
    }
}