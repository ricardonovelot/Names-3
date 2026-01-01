import SwiftUI
import SwiftData

struct NoteListRow: View {
    let note: Note
    var showContact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.content.isEmpty ? "—" : note.content)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack(spacing: 8) {
                if showContact, let contact = note.contact {
                    Text(contact.name ?? "Unknown")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if note.isLongAgo {
                    Text("Long time ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(note.creationDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}