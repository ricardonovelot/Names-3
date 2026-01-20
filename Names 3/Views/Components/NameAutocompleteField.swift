import SwiftUI
import SwiftData

struct NameAutocompleteField: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Contact> { $0.isArchived == false })
    private var contacts: [Contact]
    
    @State private var suggestedContacts: [Contact] = []
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.words)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onChange(of: text) { _, newValue in
                    filterContacts(query: newValue)
                }
            
            if !suggestedContacts.isEmpty && isFocused {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(suggestedContacts.prefix(5)) { contact in
                            Button {
                                text = contact.name ?? ""
                                suggestedContacts = []
                                onSubmit()
                            } label: {
                                HStack(spacing: 12) {
                                    if !contact.photo.isEmpty, let uiImage = UIImage(data: contact.photo) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 32, height: 32)
                                            .clipShape(Circle())
                                    } else {
                                        ZStack {
                                            RadialGradient(
                                                colors: [
                                                    Color(uiColor: .secondarySystemBackground),
                                                    Color(uiColor: .tertiarySystemBackground)
                                                ],
                                                center: .center,
                                                startRadius: 2,
                                                endRadius: 22
                                            )
                                            
                                            Color.clear
                                                .frame(width: 32, height: 32)
                                                .liquidGlass(in: Circle(), stroke: true)
                                        }
                                    }
                                    
                                    Text(contact.name ?? "Unnamed")
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                            }
                            .buttonStyle(.plain)
                            
                            if contact != suggestedContacts.prefix(5).last {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: suggestedContacts.isEmpty)
    }
    
    private func filterContacts(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.isEmpty {
            suggestedContacts = []
        } else {
            let filtered = contacts.filter { contact in
                guard let name = contact.name, !trimmed.isEmpty else { return false }
                return name.localizedStandardContains(trimmed) || 
                       name.lowercased().hasPrefix(trimmed.lowercased())
            }
            suggestedContacts = Array(filtered.prefix(5))
        }
    }
}