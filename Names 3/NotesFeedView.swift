import SwiftUI
import SwiftData

struct NotesFeedView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Note.creationDate, order: .reverse)])
    private var notes: [Note]

    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if notes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No notes yet")
                            .font(.headline)
                        Text("Add notes to your contacts and they’ll appear here in chronological order.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
                } else {
                    List {
                        ForEach(notes, id: \.self) { note in
                            NoteRow(note: note)
                                .contentShape(Rectangle())
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(note)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add note")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddNoteSheet()
        }
    }
}

private struct NoteRow: View {
    @Environment(\.modelContext) private var modelContext
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.content.isEmpty ? "—" : note.content)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack(spacing: 8) {
                if let contact = note.contact {
                    Text(contact.name ?? "Unknown")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No contact")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(note.creationDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct AddNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query
    private var contacts: [Contact]

    @State private var content: String = ""
    @State private var date: Date = Date()
    @State private var selectedContact: Contact?

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("Write a note...", text: $content, axis: .vertical)
                        .lineLimit(3...6)
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                }

                Section("Contact") {
                    Picker("Attach to", selection: $selectedContact) {
                        Text("Select a contact").tag(Optional<Contact>.none)
                        ForEach(contacts.sorted(by: { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }), id: \.self) { contact in
                            Text(contact.name ?? "Unnamed").tag(Optional<Contact>.some(contact))
                        }
                    }
                }
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        guard let selectedContact else { return false }
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedContact.id != nil
    }

    private func save() {
        guard let selectedContact else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = Note(content: trimmed, creationDate: date, contact: selectedContact)
        modelContext.insert(note)
        do {
            try modelContext.save()
        } catch {
            print("Save failed: \(error)")
        }
        dismiss()
    }
}