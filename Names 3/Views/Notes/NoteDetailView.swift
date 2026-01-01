import SwiftUI
import SwiftData

struct NoteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var note: Note

    var body: some View {
        Form {
            Section("Note") {
                TextField("Write a note...", text: $note.content, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section("Date") {
                CustomNoteDatePicker(note: note)
            }

            Section("Contact") {
                HStack {
                    Text("Attached to")
                    Spacer()
                    Text(note.contact?.name ?? "No contact")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            do {
                try modelContext.save()
            } catch {
                print("Save failed: \(error)")
            }
        }
    }
}