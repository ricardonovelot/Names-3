import SwiftUI

struct QuizPhotoCard: View {
    let contact: Contact
    /// When set, card height adapts to available space (keyboard-always-visible layout). Nil = default 280pt.
    var preferredHeight: CGFloat? = nil
    /// When true, uses tighter styling (smaller radius, shadow) for compact layouts.
    var compact: Bool = false
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var imageScale: CGFloat = 0.95
    
    private var image: UIImage? {
        guard !contact.photo.isEmpty else { return nil }
        return UIImage(data: contact.photo)
    }
    
    private var cornerRadius: CGFloat { compact ? 14 : 20 }
    private var shadowRadius: CGFloat { compact ? 6 : 10 }
    
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay(photoGradient)
                } else {
                    placeholderView(compact: compact)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(compact ? 0.12 : 0.15), radius: shadowRadius, x: 0, y: compact ? 3 : 5)
            .scaleEffect(imageScale)
        }
        .frame(height: preferredHeight ?? 280)
        .padding(.horizontal, compact ? 16 : 20)
        .onAppear {
            if !reduceMotion {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    imageScale = 1.0
                }
            } else {
                imageScale = 1.0
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(image != nil ? "Photo of person" : "No photo available")
    }
    
    private var photoGradient: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.05), location: 0.3),
                .init(color: .black.opacity(0.15), location: 0.7),
                .init(color: .black.opacity(0.25), location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private func placeholderView(compact: Bool) -> some View {
        let iconSize: CGFloat = compact ? 40 : 56
        return ZStack {
            Color(uiColor: .secondarySystemGroupedBackground).opacity(0.6)
            VStack(spacing: compact ? 6 : 12) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.system(size: iconSize, weight: .light))
                    .foregroundStyle(.quaternary)
                
                Text("No Photo")
                    .font(compact ? .caption2 : .caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
