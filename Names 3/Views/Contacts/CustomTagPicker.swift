import SwiftUI
import SwiftData

struct CustomTagPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tags: [Tag]
    @Bindable var contact: Contact
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    var body: some View{
        NavigationView{
            List{

                if !searchText.isEmpty {
                    Section{
                        Button{
                            if let tag = Tag.fetchOrCreate(named: searchText, in: modelContext) {
                                if !(contact.tags?.contains(where: { $0.normalizedKey == tag.normalizedKey }) ?? false) {
                                    if contact.tags == nil { contact.tags = [] }
                                    contact.tags?.append(tag)
                                }
                            }
                        } label: {
                            Group{
                                HStack{
                                    Text("Add \(searchText)")
                                    Image(systemName: "plus.circle.fill")
                                }
                            }
                        }
                    }
                }

                Section{
                    let uniqueTags: [Tag] = {
                        var map: [String: Tag] = [:]
                        for tag in tags {
                            let key = tag.normalizedKey
                            if map[key] == nil { map[key] = tag }
                        }
                        return map.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    }()

                    ForEach(uniqueTags, id: \.self) { tag in
                        HStack{
                            Text(tag.name)
                            Spacer()
                            if contact.tags?.contains(where: { $0.normalizedKey == tag.normalizedKey }) == true {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let existingIndex = contact.tags?.firstIndex(where: { $0.normalizedKey == tag.normalizedKey }) {
                                contact.tags?.remove(at: existingIndex)
                            } else {
                                if contact.tags == nil { contact.tags = [] }
                                contact.tags?.append(tag)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Groups & Places")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement:.navigationBarDrawer(displayMode: .always))
            .contentMargins(.top, 8)
        }
    }
}