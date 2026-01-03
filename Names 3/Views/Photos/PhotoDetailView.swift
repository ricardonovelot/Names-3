import SwiftUI
import Photos

struct PhotoDetailView: View {
    let image: UIImage
    let date: Date?
    let portalID: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @GestureState private var dragState: CGSize = .zero
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            GeometryReader { geometry in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnificationGesture)
                    .gesture(dragGesture)
                    .portal(id: portalID, .destination)
            }
            
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .padding(-8)
                            )
                    }
                    .padding()
                    
                    Spacer()
                    
                    if let date = date {
                        Text(date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            )
                            .padding()
                    }
                }
                
                Spacer()
            }
            .opacity(scale > 1.1 ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: scale)
        }
        .statusBarHidden()
        .onTapGesture(count: 2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if scale > 1.0 {
                    scale = 1.0
                    offset = .zero
                } else {
                    scale = 2.0
                }
            }
        }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale = max(1.0, min(scale * delta, 4.0))
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale < 1.0 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        scale = 1.0
                        offset = .zero
                    }
                }
            }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragState) { value, state, _ in
                state = value.translation
            }
            .onChanged { value in
                if scale > 1.0 {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                } else {
                    let progress = abs(value.translation.height) / 300
                    offset = CGSize(
                        width: value.translation.width * 0.3,
                        height: value.translation.height
                    )
                    
                    if progress > 0.3 {
                        dismiss()
                    }
                }
            }
            .onEnded { value in
                if scale > 1.0 {
                    lastOffset = offset
                } else {
                    let velocityY = value.predictedEndTranslation.height - value.translation.height
                    if abs(value.translation.height) > 150 || abs(velocityY) > 1000 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = .zero
                        }
                    }
                }
            }
    }
}