import SwiftUI
import SwiftData

struct ReviewNotesView: View {
    let contacts: [Contact]
    @Environment(\.dismiss) private var dismiss

    struct Item: Identifiable, Hashable {
        let id = UUID()
        let contact: Contact
        let note: Note
    }

    @State private var items: [Item] = []
    @State private var index: Int = 0
    @State private var revealName: Bool = false

    private var current: Item? {
        guard index >= 0 && index < items.count else { return nil }
        return items[index]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let item = current {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Note \(index + 1) of \(items.count)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(relativeDate(item.note.creationDate))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.note.content)
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("From")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if revealName {
                                    HStack {
                                        Text(item.contact.name ?? "Unknown")
                                            .font(.headline)
                                        Spacer()
                                    }
                                } else {
                                    Button {
                                        revealName = true
                                    } label: {
                                        Label("Reveal", systemImage: "eye")
                                            .font(.callout.weight(.medium))
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            if !(item.contact.tags?.isEmpty ?? true) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Groups")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text((item.contact.tags ?? []).compactMap { $0.name }.sorted().joined(separator: ", "))
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        HStack {
                            Button {
                                // open details
                            } label: {
                                NavigationLink(destination: ContactDetailsView(contact: item.contact)) {
                                    Label("Open Contact", systemImage: "person.crop.circle")
                                }
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button(nextTitle) {
                                advance()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                } else {
                    VStack(spacing: 12) {
                        Text("No recent notes")
                            .font(.headline)
                        Text("Write some notes on your contacts and come back to review them.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Close") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
                Spacer(minLength: 8)
            }
            .navigationTitle("Review Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .onAppear {
                if items.isEmpty {
                    items = buildItems(from: contacts)
                }
            }
        }
    }

    private var nextTitle: String {
        guard !items.isEmpty else { return "Close" }
        return index >= items.count - 1 ? "Finish" : "Next"
    }

    private func advance() {
        guard !items.isEmpty else { dismiss(); return }
        if index >= items.count - 1 {
            dismiss()
        } else {
            index += 1
            revealName = false
        }
    }

    private func buildItems(from contacts: [Contact]) -> [Item] {
        let pairs: [Item] = contacts.flatMap { contact in
            (contact.notes ?? []).map { note in
                Item(contact: contact, note: note)
            }
        }
        .sorted { lhs, rhs in
            lhs.note.creationDate > rhs.note.creationDate
        }

        return Array(pairs.prefix(50))
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}