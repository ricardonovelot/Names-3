import SwiftUI
import SwiftData

struct NotesQuizView: View {
    let contacts: [Contact]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "note.text")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("Notes Quiz")
                    .font(.title.bold())
                Text("Coming soon")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Notes Quiz")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}