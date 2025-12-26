import SwiftUI

struct LoadingOverlay: View {
    var message: String? = nil
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                if let message {
                    Text(message)
                        .foregroundColor(.white)
                        .font(.footnote)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .transition(.opacity)
    }
}