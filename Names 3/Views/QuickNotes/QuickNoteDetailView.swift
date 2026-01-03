import SwiftUI
import SwiftData

struct QuickNoteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var quickNote: QuickNote

    @State private var parsedContacts: [Contact] = []
    @State private var isQuickNotesActive: Bool = true
    @State private var selectedContact: Contact?

    var body: some View {
        List {
            Section("Quick Note") {
                TextEditor(text: $quickNote.content)
                    .frame(minHeight: 120)
                Toggle("Processed", isOn: $quickNote.isProcessed)
            }

            Section("Date") {
                Toggle("Long ago", isOn: $quickNote.isLongAgo)
                DatePicker("Exact Date", selection: $quickNote.date, in: ...Date(), displayedComponents: .date)
                    .disabled(quickNote.isLongAgo)
            }

            if let contacts = quickNote.linkedContacts, !contacts.isEmpty {
                Section("Linked Contacts") {
                    ForEach(contacts.sorted(by: { $0.timestamp > $1.timestamp })) { contact in
                        HStack {
                            Text(contact.name ?? "Unnamed")
                            Spacer()
                            Text(contact.timestamp, style: .date)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }

            if let notes = quickNote.linkedNotes, !notes.isEmpty {
                Section("Linked Notes") {
                    ForEach(notes.sorted(by: { $0.creationDate > $1.creationDate })) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.content)
                            HStack {
                                if let name = note.contact?.name, !name.isEmpty {
                                    Text(name)
                                }
                                Spacer()
                                Text(note.creationDate, style: .date)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Quick Note")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            QuickInputView(
                mode: .people,
                parsedContacts: $parsedContacts,
                isQuickNotesActive: $isQuickNotesActive,
                selectedContact: $selectedContact,
                linkedQuickNote: quickNote,
                allowQuickNoteCreation: false
            )
            .padding(.top, 8)
            .background(Color(UIColor.systemGroupedBackground))
        }
        .onDisappear {
            do {
                try modelContext.save()
            } catch {
                print("Save failed: \(error)")
            }
        }
    }
}