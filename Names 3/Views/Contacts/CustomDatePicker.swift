import SwiftUI
import SwiftData

struct CustomDatePicker: View {
    @Bindable var contact: Contact
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var date = Date()
    @State private var bool: Bool = false

    var body: some View {
        VStack{
            GroupBox{
                Toggle("Met long ago", isOn: $contact.isMetLongAgo)
                    .onChange(of: contact.isMetLongAgo) { _ in
                    }
                Divider()
                DatePicker("Exact Date", selection: $contact.timestamp,in: ...Date(),displayedComponents: .date)
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .disabled(contact.isMetLongAgo)

            }
            .backgroundStyle(Color(UIColor.systemBackground))
            .padding()
            Spacer()
        }
        .containerRelativeFrame([.horizontal, .vertical])
        .background(Color(UIColor.systemGroupedBackground))
    }
}