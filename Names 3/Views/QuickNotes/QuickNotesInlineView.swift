import SwiftUI
import SwiftData

struct QuickNotesInlineView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\QuickNote.date, order: .reverse)])
    private var quickNotes: [QuickNote]

    var body: some View {
        Group {
            if quickNotes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No quick notes")
                        .font(.headline)
                    Text("Type “quick”, “quick note”, or “qn” to capture a quick note.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
            } else {
                List {
                    ForEach(quickNotes, id: \.self) { qn in
                        QuickNoteEditableRow(quickNote: qn)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(qn.isProcessed ? "Unprocess" : "Processed") {
                                    qn.isProcessed.toggle()
                                    try? modelContext.save()
                                }
                                .tint(qn.isProcessed ? .orange : .green)

                                Button(role: .destructive) {
                                    modelContext.delete(qn)
                                    try? modelContext.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}