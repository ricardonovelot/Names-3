import SwiftUI
import SwiftData
import Vision

struct FaceAssignmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let sourceImage: UIImage
    let detectedFaces: [DetectedFaceInfo]
    let targetContact: Contact?
    let onComplete: ([AssignedFace]) -> Void
    
    @State private var faceAssignments: [FaceAssignment] = []
    @State private var selectedFaceIndex: Int = 0
    
    struct DetectedFaceInfo: Identifiable {
        let id = UUID()
        let image: UIImage
        let boundingBox: CGRect
    }
    
    struct FaceAssignment: Identifiable {
        let id = UUID()
        let faceInfo: DetectedFaceInfo
        var assignedName: String = ""
    }
    
    struct AssignedFace {
        let image: UIImage
        let name: String
        let boundingBox: CGRect
    }
    
    init(sourceImage: UIImage, detectedFaces: [DetectedFaceInfo], targetContact: Contact?, onComplete: @escaping ([AssignedFace]) -> Void) {
        self.sourceImage = sourceImage
        self.detectedFaces = detectedFaces
        self.targetContact = targetContact
        self.onComplete = onComplete
        
        _faceAssignments = State(initialValue: detectedFaces.map { FaceAssignment(faceInfo: $0) })
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Name the detected faces")
                    .font(.headline)
                    .padding(.top)
                
                facesCarousel
                
                nameInputSection
                
                readyToAssignSection
                
                Spacer()
            }
            .padding()
            .navigationTitle("Assign Names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveAssignments()
                    }
                    .disabled(readyToAssign.isEmpty)
                }
            }
        }
    }
    
    private var facesCarousel: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(faceAssignments.indices, id: \.self) { index in
                        VStack(spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                Image(uiImage: faceAssignments[index].faceInfo.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                selectedFaceIndex == index ? Color.accentColor : Color.clear,
                                                lineWidth: 3
                                            )
                                    }
                                
                                if faceAssignments[index].assignedName.isEmpty {
                                    Image(systemName: "questionmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Color.white, Color.accentColor)
                                        .font(.title2)
                                } else {
                                    Image(systemName: "checkmark.seal.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Color.white, Color.green)
                                        .font(.title2)
                                }
                            }
                            
                            Text(faceAssignments[index].assignedName.isEmpty ? "Tap to name" : faceAssignments[index].assignedName)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(width: 100)
                        }
                        .onTapGesture {
                            selectedFaceIndex = index
                            withAnimation {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: selectedFaceIndex) { oldValue, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .frame(height: 140)
    }
    
    private var nameInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name for Face \(selectedFaceIndex + 1)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            NameAutocompleteField(
                text: Binding(
                    get: { 
                        guard selectedFaceIndex < faceAssignments.count else { return "" }
                        return faceAssignments[selectedFaceIndex].assignedName 
                    },
                    set: { newValue in
                        guard selectedFaceIndex < faceAssignments.count else { return }
                        faceAssignments[selectedFaceIndex].assignedName = newValue
                    }
                ),
                placeholder: "Type a name and press return",
                onSubmit: {
                    if selectedFaceIndex < faceAssignments.count - 1 {
                        selectedFaceIndex += 1
                    }
                }
            )
        }
    }
    
    private var readyToAssignSection: some View {
        Group {
            if !readyToAssign.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ready to Assign (\(readyToAssign.count))")
                        .font(.headline)
                    
                    ForEach(readyToAssign) { assignment in
                        HStack(spacing: 12) {
                            Image(uiImage: assignment.faceInfo.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            
                            Text(assignment.assignedName)
                                .font(.body)
                            
                            Spacer()
                            
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var readyToAssign: [FaceAssignment] {
        faceAssignments.filter { !$0.assignedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    
    private func saveAssignments() {
        let assigned = readyToAssign.map { assignment in
            AssignedFace(
                image: assignment.faceInfo.image,
                name: assignment.assignedName.trimmingCharacters(in: .whitespacesAndNewlines),
                boundingBox: assignment.faceInfo.boundingBox
            )
        }
        
        onComplete(assigned)
        dismiss()
    }
}