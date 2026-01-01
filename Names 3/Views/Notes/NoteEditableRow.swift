import SwiftUI
import SwiftData

struct NoteEditableRow: View {
    @Bindable var note: Note
    var showContact: Bool = false

    @State private var showDatePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Note Content", text: $note.content, axis: .vertical)
                .lineLimit(2...)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                if showContact, let contact = note.contact {
                    Text(contact.name ?? "Unknown")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Group {
                    if note.isLongAgo {
                        Text("Long time ago")
                    } else {
                        Text(note.creationDate, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .onTapGesture {
                    showDatePicker = true
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .sheet(isPresented: $showDatePicker) {
            CustomNoteDatePicker(note: note)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}