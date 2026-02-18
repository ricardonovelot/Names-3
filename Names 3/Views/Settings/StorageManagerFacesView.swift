//
//  StorageManagerFacesView.swift
//  Names 3
//
//  Identify and delete face data to free storage.
//

import SwiftUI
import SwiftData

struct StorageManagerFacesView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var unassignedCount = 0
    @State private var unassignedSize: Int64 = 0
    @State private var byContact: [(name: String, uuid: UUID, count: Int, size: Int64)] = []
    @State private var isLoading = true
    @State private var showDeleteUnassignedConfirmation = false
    @State private var contactToDeleteFaces: (name: String, uuid: UUID, count: Int)?
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text(String(localized: "storage.calculating"))
                        .foregroundStyle(.secondary)
                }
            } else {
                if unassignedCount > 0 {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "storage.faces.unassigned"))
                                    .font(.body)
                                Text(String(format: String(localized: "storage.app.faces.count"), unassignedCount))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: unassignedSize, countStyle: .file))
                                .foregroundStyle(.secondary)
                            Button(String(localized: "storage.delete"), role: .destructive) {
                                showDeleteUnassignedConfirmation = true
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey("storage.faces.unassigned.header"))
                    } footer: {
                        Text(LocalizedStringKey("storage.faces.unassigned.footer"))
                    }
                }
                
                if !byContact.isEmpty {
                    Section {
                        ForEach(byContact, id: \.uuid) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name.isEmpty ? String(localized: "storage.unnamed") : item.name)
                                        .font(.body)
                                    Text(String(format: String(localized: "storage.app.faces.count"), item.count))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                    .foregroundStyle(.secondary)
                                Button(String(localized: "storage.delete"), role: .destructive) {
                                    contactToDeleteFaces = (item.name, item.uuid, item.count)
                                }
                            }
                        }
                    } header: {
                        Text(LocalizedStringKey("storage.faces.byContact.header"))
                    } footer: {
                        Text(LocalizedStringKey("storage.faces.byContact.footer"))
                    }
                }
                
                if unassignedCount == 0 && byContact.isEmpty {
                    ContentUnavailableView(
                        String(localized: "storage.faces.empty.title"),
                        systemImage: "face.smiling",
                        description: Text(String(localized: "storage.faces.empty.subtitle"))
                    )
                }
            }
        }
        .navigationTitle(String(localized: "storage.app.faces"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(String(localized: "storage.faces.deleteUnassigned.title"), isPresented: $showDeleteUnassignedConfirmation) {
            Button(String(format: String(localized: "storage.faces.deleteUnassigned.action"), unassignedCount), role: .destructive) {
                deleteUnassignedFaces()
                showDeleteUnassignedConfirmation = false
            }
            Button(String(localized: "storage.cancel"), role: .cancel) { showDeleteUnassignedConfirmation = false }
        } message: {
            Text(String(format: String(localized: "storage.faces.deleteUnassigned.message"), unassignedCount))
        }
        .confirmationDialog(String(localized: "storage.faces.deleteForContact.title"), isPresented: Binding(
            get: { contactToDeleteFaces != nil },
            set: { if !$0 { contactToDeleteFaces = nil } }
        )) {
            if let item = contactToDeleteFaces {
                Button(String(localized: "storage.faces.deleteForContact.action"), role: .destructive) {
                    deleteFacesForContact(uuid: item.uuid)
                    contactToDeleteFaces = nil
                }
            }
            Button(String(localized: "storage.cancel"), role: .cancel) { contactToDeleteFaces = nil }
        } message: {
            if let item = contactToDeleteFaces {
                Text(String(format: String(localized: "storage.faces.deleteForContact.message"), item.count, item.name.isEmpty ? String(localized: "storage.unnamed") : item.name))
            }
        }
    }
    
    private func load() async {
        isLoading = true
        let result = StorageManagerService.shared.fetchFacesBreakdown(context: modelContext)
        unassignedCount = result.unassignedCount
        unassignedSize = result.unassignedSize
        byContact = result.byContact
        isLoading = false
    }
    
    private func deleteUnassignedFaces() {
        StorageManagerService.shared.deleteUnassignedFaces(context: modelContext)
        Task { await load() }
    }
    
    private func deleteFacesForContact(uuid: UUID) {
        StorageManagerService.shared.deleteFacesForContact(uuid: uuid, context: modelContext)
        Task { await load() }
    }
}
