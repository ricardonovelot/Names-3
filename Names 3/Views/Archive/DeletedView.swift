import SwiftUI
import SwiftData

struct DeletedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editMode) private var editMode

    @Query(filter: #Predicate<Contact> { $0.isArchived == true })
    private var deletedContacts: [Contact]

    @Query(filter: #Predicate<Note> { $0.isArchived == true })
    private var deletedNotes: [Note]

    @State private var category: Category = .contacts
    @State private var selectedContactIDs: Set<PersistentIdentifier> = []
    @State private var selectedNoteIDs: Set<PersistentIdentifier> = []

    enum Category: String, CaseIterable, Identifiable {
        case contacts = "Contacts"
        case notes = "Notes"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Picker("Category", selection: $category) {
                    ForEach(Category.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if category == .contacts {
                    List(selection: $selectedContactIDs) {
                        ForEach(deletedContacts) { contact in
                            HStack {
                                Text(contact.name?.isEmpty == false ? (contact.name ?? "Unnamed") : "Unnamed")
                                Spacer()
                                if let when = contact.archivedDate {
                                    Text(when, style: .date)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(contact.persistentModelID)
                        }
                    }
                } else {
                    List(selection: $selectedNoteIDs) {
                        ForEach(deletedNotes) { note in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.content)
                                if let when = note.archivedDate {
                                    Text(when, style: .date)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(note.persistentModelID)
                        }
                    }
                }
            }
            .navigationTitle("Deleted")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }

                if isEditing {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("Restore", systemImage: "arrow.uturn.backward") {
                            restoreSelected()
                        }
                        .disabled(!hasSelection)

                        Spacer()

                        Button("Delete", systemImage: "trash") {
                            deleteSelectedPermanently()
                        }
                        .tint(.red)
                        .disabled(!hasSelection)
                    }
                }
            }
            .toolbarBackground(isEditing ? .visible : .hidden, for: .bottomBar)
            .animation(.snappy, value: isEditing)
        }
        .onChange(of: isEditing) { _, newIsEditing in
            if !newIsEditing {
                selectedContactIDs.removeAll()
                selectedNoteIDs.removeAll()
            }
        }
        .onChange(of: category) {
            selectedContactIDs.removeAll()
            selectedNoteIDs.removeAll()
        }
    }

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    private var hasSelection: Bool {
        switch category {
        case .contacts: return !selectedContactIDs.isEmpty
        case .notes: return !selectedNoteIDs.isEmpty
        }
    }

    private func restoreSelected() {
        switch category {
        case .contacts:
            for id in selectedContactIDs {
                if let c = deletedContacts.first(where: { $0.persistentModelID == id }) {
                    c.isArchived = false
                    c.archivedDate = nil
                }
            }
        case .notes:
            for id in selectedNoteIDs {
                if let n = deletedNotes.first(where: { $0.persistentModelID == id }) {
                    n.isArchived = false
                    n.archivedDate = nil
                }
            }
        }
        save()
    }

    private func deleteSelectedPermanently() {
        switch category {
        case .contacts:
            for id in selectedContactIDs {
                if let c = deletedContacts.first(where: { $0.persistentModelID == id }) {
                    modelContext.delete(c)
                }
            }
        case .notes:
            for id in selectedNoteIDs {
                if let n = deletedNotes.first(where: { $0.persistentModelID == id }) {
                    modelContext.delete(n)
                }
            }
        }
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Save failed: \(error)")
        }
        selectedContactIDs.removeAll()
        selectedNoteIDs.removeAll()
    }
}
