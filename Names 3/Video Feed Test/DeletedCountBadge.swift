import SwiftUI

struct DeletedCountBadge: View {
    @State private var count: Int = 0

    var body: some View {
        Text("\(count)")
            .font(.footnote.monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.secondary.opacity(0.15))
            )
            .onAppear {
                refresh()
                NotificationCenter.default.addObserver(forName: .deletedVideosChanged, object: nil, queue: .main) { _ in
                    refresh()
                }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self, name: .deletedVideosChanged, object: nil)
            }
            .accessibilityLabel("Deleted videos count \(count)")
    }

    private func refresh() {
        count = DeletedVideosStore.snapshot().count
    }
}