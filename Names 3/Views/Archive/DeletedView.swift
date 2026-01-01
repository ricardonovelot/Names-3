import SwiftUI
import SwiftData

struct DeletedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Contact> { $0.isArchived == true })
    private var deletedContacts: [Contact]

    @Query(filter: #Predicate<Note> { $0.isArchived == true })
    private var deletedNotes: [Note]
    
    @Query(filter: #Predicate<Tag> { $0.isArchived == true })
    private var deletedTags: [Tag]

    @State private var editMode: EditMode = .inactive
    @State private var category: Category = .contacts
    @State private var selectedContactIDs: Set<PersistentIdentifier> = []
    @State private var selectedNoteIDs: Set<PersistentIdentifier> = []
    @State private var selectedTagIDs: Set<PersistentIdentifier> = []
    @State private var isShowingConfirmation = false
    @State private var pendingAction: PendingAction?

    enum Category: String, CaseIterable, Identifiable {
        case contacts = "Contacts"
        case notes = "Notes"
        case tags = "Tags"
        var id: String { rawValue }
    }

    private enum PendingAction {
        case restore
        case delete
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
                    .environment(\.editMode, $editMode)
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                } else if category == .notes {
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
                    .environment(\.editMode, $editMode)
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                } else {
                    List(selection: $selectedTagIDs) {
                        ForEach(deletedTags) { tag in
                            HStack {
                                Text(tag.name)
                                Spacer()
                                if let when = tag.archivedDate {
                                    Text(when, style: .date)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(tag.persistentModelID)
                        }
                    }
                    .environment(\.editMode, $editMode)
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
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

                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Restore") {
                        pendingAction = .restore
                        isShowingConfirmation = true
                    }
                    .disabled(!hasSelection)

                    Spacer()

                    Button("Delete Permanently") {
                        pendingAction = .delete
                        isShowingConfirmation = true
                    }
                    .tint(.red)
                    .disabled(!hasSelection)
                }
            }
            .toolbarBackground(.visible, for: .bottomBar)
            .animation(.snappy, value: isEditing)
        }
        .environment(\.editMode, $editMode)
        .alert("Confirm action", isPresented: $isShowingConfirmation, presenting: pendingAction) { action in
            switch action {
            case .restore:
                Button("Restore") {
                    restoreSelected()
                    pendingAction = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingAction = nil
                }
            case .delete:
                Button("Delete", role: .destructive) {
                    deleteSelectedPermanently()
                    pendingAction = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingAction = nil
                }
            }
        } message: { action in
            let count = selectionCount
            let noun = pluralizedCategory(for: count)
            switch action {
            case .restore:
                Text("Are you sure you want to restore \(count) \(noun)?")
            case .delete:
                Text("Are you sure you want to permanently delete \(count) \(noun)? This cannot be undone.")
            }
        }
        .onChange(of: editMode) { _, newValue in
            if !newValue.isEditing {
                selectedContactIDs.removeAll()
                selectedNoteIDs.removeAll()
                selectedTagIDs.removeAll()
            }
        }
        .onChange(of: category) { _ in
            selectedContactIDs.removeAll()
            selectedNoteIDs.removeAll()
            selectedTagIDs.removeAll()
        }
    }

    private var isEditing: Bool {
        editMode.isEditing
    }

    private var hasSelection: Bool {
        switch category {
        case .contacts: return !selectedContactIDs.isEmpty
        case .notes: return !selectedNoteIDs.isEmpty
        case .tags: return !selectedTagIDs.isEmpty
        }
    }

    private var selectionCount: Int {
        switch category {
        case .contacts: return selectedContactIDs.count
        case .notes: return selectedNoteIDs.count
        case .tags: return selectedTagIDs.count
        }
    }

    private func pluralizedCategory(for count: Int) -> String {
        switch category {
        case .contacts: return count == 1 ? "contact" : "contacts"
        case .notes: return count == 1 ? "note" : "notes"
        case .tags: return count == 1 ? "tag" : "tags"
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
        case .tags:
            for id in selectedTagIDs {
                if let t = deletedTags.first(where: { $0.persistentModelID == id }) {
                    t.isArchived = false
                    t.archivedDate = nil
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
        case .tags:
            for id in selectedTagIDs {
                if let t = deletedTags.first(where: { $0.persistentModelID == id }) {
                    modelContext.delete(t)
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
        selectedTagIDs.removeAll()
    }
}