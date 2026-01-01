import SwiftUI
import SwiftData

struct TagPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Tag> { $0.isArchived == false }) private var tags: [Tag]

    enum Mode {
        case contactToggle(contact: Contact)
        case groupApply(onApply: (Tag) -> Void)
        case manage
    }

    let mode: Mode

    @State private var searchText: String = ""
    @State private var selectedForGroup: Tag?
    @State private var renamingTag: Tag?
    @State private var renameText: String = ""
    @State private var isRenaming: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Button {
                            let name = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let created = Tag.fetchOrCreate(named: name, in: modelContext) {
                                switch mode {
                                case .contactToggle(let contact):
                                    toggle(tag: created, for: contact)
                                case .groupApply:
                                    selectedForGroup = created
                                case .manage:
                                    // No selection; just create
                                    break
                                }
                                searchText = ""
                            }
                        } label: {
                            HStack {
                                Text("Add \(searchText)")
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                    }
                }

                Section {
                    let uniqueTags = uniqueSortedTags()
                    ForEach(uniqueTags, id: \.normalizedKey) { tag in
                        HStack {
                            Text(tag.name)
                            Spacer()
                            if isSelected(tag: tag) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            switch mode {
                            case .contactToggle(let contact):
                                toggle(tag: tag, for: contact)
                            case .groupApply:
                                selectedForGroup = tag
                            case .manage:
                                break
                            }
                        }
                        .swipeActions {
                            Button {
                                renamingTag = tag
                                renameText = tag.name
                                isRenaming = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.orange)
                            
                            Button(role: .destructive) {
                                archive(tag: tag)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Groups & Places")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                switch mode {
                case .contactToggle:
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                case .groupApply(let onApply):
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Apply") {
                            if let chosen = selectedForGroup {
                                onApply(chosen)
                                dismiss()
                            } else if let created = Tag.fetchOrCreate(named: searchText.trimmingCharacters(in: .whitespacesAndNewlines), in: modelContext) {
                                onApply(created)
                                dismiss()
                            }
                        }
                        .disabled(selectedForGroup == nil && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                case .manage:
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $isRenaming) {
                NavigationStack {
                    Form {
                        Section("Rename tag") {
                            TextField("Name", text: $renameText)
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(false)
                        }
                    }
                    .navigationTitle("Rename Tag")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                isRenaming = false
                                renamingTag = nil
                                renameText = ""
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Save") {
                                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if let t = renamingTag, !trimmed.isEmpty {
                                    _ = Tag.rename(t, to: trimmed, in: modelContext)
                                }
                                isRenaming = false
                                renamingTag = nil
                                renameText = ""
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func uniqueSortedTags() -> [Tag] {
        var map: [String: Tag] = [:]
        for t in tags {
            let key = t.normalizedKey
            if map[key] == nil { map[key] = t }
        }
        return map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func isSelected(tag: Tag) -> Bool {
        switch mode {
        case .contactToggle(let contact):
            return (contact.tags ?? []).contains(where: { $0.normalizedKey == tag.normalizedKey })
        case .groupApply:
            return selectedForGroup?.normalizedKey == tag.normalizedKey
        case .manage:
            return false
        }
    }

    private func toggle(tag: Tag, for contact: Contact) {
        var arr = contact.tags ?? []
        if let idx = arr.firstIndex(where: { $0.normalizedKey == tag.normalizedKey }) {
            arr.remove(at: idx)
        } else {
            arr.append(tag)
        }
        contact.tags = arr
        do {
            try modelContext.save()
        } catch {
            print("Save failed: \(error)")
        }
    }
    
    private func archive(tag: Tag) {
        tag.isArchived = true
        tag.archivedDate = Date()
        do {
            try modelContext.save()
        } catch {
            print("Save failed: \(error)")
        }
    }
}

extension Tag {
    @MainActor
    static func rename(_ tag: Tag, to newName: String, in context: ModelContext) -> Tag {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return tag }
        if let existing = find(named: trimmed, in: context), existing !== tag {
            let impacted = tag.contacts ?? []
            for contact in impacted {
                var arr = contact.tags ?? []
                arr.removeAll(where: { $0 === tag })
                if !arr.contains(where: { $0 === existing }) {
                    arr.append(existing)
                }
                contact.tags = arr
            }
            existing.isArchived = false
            existing.archivedDate = nil
            context.delete(tag)
            do { try context.save() } catch { print("Save failed: \(error)") }
            return existing
        } else {
            tag.name = trimmed
            do { try context.save() } catch { print("Save failed: \(error)") }
            return tag
        }
    }
}