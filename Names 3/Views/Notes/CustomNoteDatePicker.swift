import SwiftUI
import SwiftData

struct CustomNoteDatePicker: View {
    @Bindable var note: Note

    var body: some View {
        GroupBox {
            Toggle("Long ago", isOn: $note.isLongAgo)
            Divider()
            DatePicker("Exact Date", selection: $note.creationDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(GraphicalDatePickerStyle())
                .disabled(note.isLongAgo)
        }
        .backgroundStyle(Color(UIColor.systemBackground))
    }
}