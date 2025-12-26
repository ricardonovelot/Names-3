import SwiftUI

struct PhotosDayPickerHost: View {
    let day: Date
    let onPick: (UIImage) -> Void
    @State private var showSpinner = true

    var body: some View {
        ZStack {
            PhotosDayPickerView(day: day) { image in
                onPick(image)
            }

            if showSpinner {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading photos…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                showSpinner = false
            }
        }
    }
}