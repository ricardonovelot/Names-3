import SwiftUI
import SwiftData

struct QuickInputFaceView: View {
    @Binding var detectedFaces: [FaceDetectionViewModel.DetectedFace]
    let onFaceSelected: (Int) -> Void
    
    @State private var text: String = ""
    @FocusState private var fieldIsFocused: Bool
    @State private var faceChipsHeight: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Face chips showing above input
            if !detectedFaces.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(detectedFaces.enumerated()), id: \.offset) { index, face in
                            FaceChipView(
                                face: face,
                                index: index,
                                onTap: {
                                    onFaceSelected(index)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: FaceChipsHeightKey.self, value: proxy.size.height)
                    }
                )
                .onPreferenceChange(FaceChipsHeightKey.self) { height in
                    faceChipsHeight = height
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            
            // Text input
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        GrowingTextView(
                            text: $text,
                            isFirstResponder: Binding(
                                get: { fieldIsFocused },
                                set: { fieldIsFocused = $0 }
                            ),
                            minHeight: 22,
                            maxHeight: 140,
                            onDeleteWhenEmpty: { },
                            onReturn: { }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .onChange(of: text) { oldValue, newValue in
                            mapTextToFaces(newValue)
                        }
                        
                        if text.isEmpty {
                            Text("Type names separated by commas")
                                .foregroundStyle(.secondary)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
                .clipShape(.rect(cornerRadius: 24))
                .frame(minHeight: 44)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .preference(key: TotalQuickInputHeightKey.self, value: faceChipsHeight + 60)
        .onReceive(NotificationCenter.default.publisher(for: .quickInputRequestFocus)) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                fieldIsFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickInputResignFocus)) { _ in
            fieldIsFocused = false
        }
    }
    
    private func mapTextToFaces(_ rawText: String) {
        let parts = rawText.split(separator: ",", omittingEmptySubsequences: false)
        
        for (index, part) in parts.enumerated() where index < detectedFaces.count {
            let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            detectedFaces[index].name = name.isEmpty ? nil : name
        }
    }
}

struct FaceChipView: View {
    let face: FaceDetectionViewModel.DetectedFace
    let index: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(uiImage: face.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(face.name ?? "Face \(index + 1)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if face.name == nil {
                        Text("Tap to name")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if face.name != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                face.name != nil 
                    ? Color.green.opacity(0.15)
                    : Color.secondary.opacity(0.1)
            )
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct FaceChipsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}