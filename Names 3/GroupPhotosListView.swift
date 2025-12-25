import SwiftUI
import SwiftData

struct GroupPhotosListView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\FaceBatch.createdAt, order: .reverse)]) private var batches: [FaceBatch]
    let contactsContext: ModelContext

    var body: some View {
        NavigationStack {
            List {
                if batches.isEmpty {
                    ContentUnavailableView {
                        Label("No Group Photos", systemImage: "person.3")
                    } description: {
                        Text("Create a new group from Bulk add faces.")
                    }
                } else {
                    ForEach(batches, id: \.self) { batch in
                        NavigationLink {
                            BulkAddFacesView(existingBatch: batch, contactsContext: contactsContext)
                                .modelContainer(BatchModelContainer.shared)
                        } label: {
                            HStack(spacing: 12) {
                                if let img = UIImage(data: batch.image) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(batch.groupName.isEmpty ? "Untitled Group" : batch.groupName)
                                        .font(.headline)
                                    Text(batch.date, style: .date)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let faces = batch.faces {
                                    let done = faces.filter { !$0.assignedName.isEmpty && $0.exported }.count
                                    let total = faces.count
                                    Text("\(done)/\(total)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Group Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            }
        }
    }
}