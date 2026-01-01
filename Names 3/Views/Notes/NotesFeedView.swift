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
                            NoteEditableRow(note: note, showContact: true)
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

struct AddNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query
    private var contacts: [Contact]

    @State private var content: String = ""
    @State private var date: Date = Date()
    @State private var isLongAgo: Bool = false
    @State private var selectedContact: Contact?
    @State private var showContactSelect: Bool = false

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextField("Write a note...", text: $content, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Date") {
                    Toggle("Long ago", isOn: $isLongAgo)
                    DatePicker("Exact Date", selection: $date, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.automatic)
                        .disabled(isLongAgo)
                }

                Section("Contact") {
                    Button {
                        showContactSelect = true
                    } label: {
                        HStack {
                            Text("Attach to")
                            Spacer()
                            Text(selectedContact?.name ?? "Select or create")
                                .foregroundStyle(.secondary)
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
        .sheet(isPresented: $showContactSelect) {
            ContactSelectView { contact in
                selectedContact = contact
                showContactSelect = false
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
        let note = Note(content: trimmed, creationDate: date, isLongAgo: isLongAgo, contact: selectedContact)
        modelContext.insert(note)
        do {
            try modelContext.save()
        } catch {
            print("Save failed: \(error)")
        }
        dismiss()
    }
}