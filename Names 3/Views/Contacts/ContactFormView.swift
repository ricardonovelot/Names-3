import SwiftUI
import SwiftData

struct ContactFormView: View {
    @Bindable var contact: Contact

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $contact.name ?? "")
            }
        }
    }
}