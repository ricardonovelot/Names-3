import SwiftUI

struct QuizPhotoCard: View {
    let contact: Contact
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var imageScale: CGFloat = 0.95
    
    private var image: UIImage? {
        guard !contact.photo.isEmpty else { return nil }
        return UIImage(data: contact.photo)
    }
    
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
                    placeholderView
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            .scaleEffect(imageScale)
        }
        .frame(height: 280)
        .padding(.horizontal, 20)
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
    
    private var placeholderView: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(uiColor: .secondarySystemBackground),
                    Color(uiColor: .tertiarySystemBackground)
                ],
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
            
            VStack(spacing: 12) {
                Image(systemName: "person.crop.square.filled.and.at.rectangle")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.quaternary)
                
                Text("No Photo")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}