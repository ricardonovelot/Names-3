import SwiftUI
import SwiftData

struct ContactSelectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var contacts: [Contact]

    @State private var searchText: String = ""
    @State private var navigateNew: Bool = false
    @State private var created: Contact?

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
                        navigateNew = true
                    } label: {
                        Label("New", systemImage: "person.badge.plus")
                    }
                }
            }
            .background(
                NavigationLink(
                    destination: {
                        if let c = created {
                            ContactDetailsView(contact: c)
                        }
                    },
                    isActive: $navigateNew
                ) { EmptyView() }
                .hidden()
            )
        }
    }

    private func filteredContacts() -> [Contact] {
        let list = contacts.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return list }
        return list.filter { ($0.name ?? "").localizedCaseInsensitiveContains(q) }
    }
}