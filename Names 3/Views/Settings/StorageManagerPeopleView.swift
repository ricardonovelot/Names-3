//
//  StorageManagerPeopleView.swift
//  Names 3
//
//  Identify and delete contact photos to free storage.
//

import SwiftUI
import SwiftData

struct StorageManagerPeopleView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var items: [(contact: Contact, size: Int64)] = []
    @State private var isLoading = true
    @State private var contactToClear: Contact?
    @State private var contactToDelete: Contact?
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text(String(localized: "storage.calculating"))
                        .foregroundStyle(.secondary)
                }
            } else if items.isEmpty {
                ContentUnavailableView(
                    String(localized: "storage.people.empty.title"),
                    systemImage: "person.2",
                    description: Text(String(localized: "storage.people.empty.subtitle"))
                )
            } else {
                Section {
                    ForEach(items, id: \.contact.uuid) { item in
                        ContactPhotoRow(
                            contact: item.contact,
                            size: item.size,
                            onClearPhoto: { contactToClear = item.contact },
                            onDeleteContact: { contactToDelete = item.contact }
                        )
                    }
                } header: {
                    Text(LocalizedStringKey("storage.people.section.header"))
                } footer: {
                    Text(LocalizedStringKey("storage.people.section.footer"))
                }
            }
        }
        .navigationTitle(String(localized: "storage.app.people"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(String(localized: "storage.people.clearPhoto.title"), isPresented: Binding(
            get: { contactToClear != nil },
            set: { if !$0 { contactToClear = nil } }
        )) {
            if let c = contactToClear {
                Button(String(localized: "storage.people.clearPhoto.action"), role: .destructive) {
                    clearPhoto(c)
                    contactToClear = nil
                }
            }
            Button(String(localized: "storage.cancel"), role: .cancel) { contactToClear = nil }
        } message: {
            if let c = contactToClear {
                Text(String(format: String(localized: "storage.people.clearPhoto.message"), c.name ?? "Unknown"))
            }
        }
        .confirmationDialog(String(localized: "storage.people.deleteContact.title"), isPresented: Binding(
            get: { contactToDelete != nil },
            set: { if !$0 { contactToDelete = nil } }
        )) {
            if let c = contactToDelete {
                Button(String(localized: "storage.people.deleteContact.action"), role: .destructive) {
                    deleteContact(c)
                    contactToDelete = nil
                }
            }
            Button(String(localized: "storage.cancel"), role: .cancel) { contactToDelete = nil }
        } message: {
            if let c = contactToDelete {
                Text(String(format: String(localized: "storage.people.deleteContact.message"), c.name ?? "Unknown"))
            }
        }
    }
    
    private func load() async {
        isLoading = true
        items = StorageManagerService.shared.fetchContactsWithPhotoSizes(context: modelContext)
        isLoading = false
    }
    
    private func clearPhoto(_ contact: Contact) {
        StorageManagerService.shared.clearContactPhoto(contact)
        try? modelContext.save()
        Task { await load() }
    }
    
    private func deleteContact(_ contact: Contact) {
        StorageManagerService.shared.deleteContact(contact, context: modelContext)
        Task { await load() }
    }
}

private struct ContactPhotoRow: View {
    let contact: Contact
    let size: Int64
    let onClearPhoto: () -> Void
    let onDeleteContact: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if !contact.photo.isEmpty, let img = UIImage(data: contact.photo) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name ?? String(localized: "storage.unnamed"))
                    .font(.body)
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button(role: .destructive, action: onClearPhoto) {
                    Label(String(localized: "storage.people.clearPhoto.action"), systemImage: "photo.badge.minus")
                }
                Button(role: .destructive, action: onDeleteContact) {
                    Label(String(localized: "storage.people.deleteContact.action"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
            }
        }
        .padding(.vertical, 4)
    }
}
