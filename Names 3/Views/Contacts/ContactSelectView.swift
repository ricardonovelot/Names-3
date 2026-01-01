import SwiftUI
import SwiftData

struct ContactSelectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var contacts: [Contact]

    @State private var searchText: String = ""
    @State private var navigateNew: Bool = false
    @State private var created: Contact?
    @State private var showCreateSheet: Bool = false

    let onSelect: (Contact) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredContacts(), id: \.self) { contact in
                    Button {
                        onSelect(contact)
                        dismiss()
                    } label: {
                        HStack {
                            Text(contact.name ?? "Unnamed")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Select Contact")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let newContact = Contact()
                        modelContext.insert(newContact)
                        created = newContact
                        showCreateSheet = true
                    } label: {
                        Label("New", systemImage: "person.badge.plus")
                    }
                }
            }
            .background(
                NavigationLink(
                    destination: OptionalContactDetails(contact: created),
                    isActive: $navigateNew,
                    label: { EmptyView() }
                )
                .hidden()
            )
        }
        .sheet(isPresented: $showCreateSheet) {
            if let c = created {
                NavigationStack {
                    ContactDetailsView(
                        contact: c,
                        isCreationFlow: true,
                        onSave: {
                            // Ensure saved already inside ContactDetailsView
                            showCreateSheet = false
                            onSelect(c)
                        },
                        onCancel: {
                            if let toDelete = created {
                                modelContext.delete(toDelete)
                                do { try modelContext.save() } catch { print("Save failed: \(error)") }
                            }
                            created = nil
                            showCreateSheet = false
                        }
                    )
                }
            }
        }
    }

    private func filteredContacts() -> [Contact] {
        let list = contacts.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return list }
        return list.filter { ($0.name ?? "").localizedCaseInsensitiveContains(q) }
    }
}

private struct OptionalContactDetails: View {
    let contact: Contact?

    var body: some View {
        Group {
            if let c = contact {
                ContactDetailsView(contact: c)
            } else {
                EmptyView()
            }
        }
    }
}