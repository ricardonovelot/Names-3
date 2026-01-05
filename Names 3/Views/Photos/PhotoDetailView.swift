import SwiftUI
import SwiftData
import Vision

struct SelectedPhoto: Identifiable, Hashable {
    let id = UUID()
    let image: UIImage
    let date: Date?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SelectedPhoto, rhs: SelectedPhoto) -> Bool {
        lhs.id == rhs.id
    }
}

struct PhotoDetailView: View {
    let photo: SelectedPhoto
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var viewModel = FaceDetectionViewModel()
    @State private var currentImage: UIImage
    @State private var detectedDate: Date
    @State private var globalGroupText: String = ""
    @State private var showCropper = false
    
    @State private var parsedContacts: [Contact] = []
    @State private var isQuickNotesActive: Bool = false
    @State private var selectedContact: Contact? = nil
    
    init(photo: SelectedPhoto) {
        self.photo = photo
        self._currentImage = State(initialValue: photo.image)
        self._detectedDate = State(initialValue: photo.date ?? Date())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            photoHeaderSection
            
            ScrollView {
                VStack(spacing: 20) {
                    photoDetailsSection
                    
                    if !viewModel.faces.isEmpty {
                        instructionSection
                    } else if !viewModel.isDetecting {
                        noFacesView
                    }
                }
                .padding()
                .contentShape(.rect)
                .onTapGesture {
                    NotificationCenter.default.post(name: .quickInputResignFocus, object: nil)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    saveAll()
                }
                .disabled(readyToAddFaces.isEmpty)
            }
        }
        .task {
            await viewModel.detectFaces(in: photo.image)
            // Request focus after face detection completes
            try? await Task.sleep(for: .milliseconds(150))
            NotificationCenter.default.post(name: .quickInputRequestFocus, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickInputTextDidChange)) { output in
            if let text = output.userInfo?["text"] as? String {
                mapRawTextToFaces(text)
            }
        }
        .fullScreenCover(isPresented: $showCropper) {
            SimpleCropView(image: currentImage) { cropped in
                if let cropped {
                    currentImage = cropped
                    Task {
                        await viewModel.detectFaces(in: cropped)
                    }
                }
                showCropper = false
            }
        }
        .safeAreaInset(edge: .bottom) {
            QuickInputView(
                mode: .people,
                parsedContacts: $parsedContacts,
                isQuickNotesActive: $isQuickNotesActive,
                selectedContact: $selectedContact,
                onCameraTap: nil,
                allowQuickNoteCreation: false
            )
        }
    }
    
    private var photoHeaderSection: some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: currentImage)
                .resizable()
                .scaledToFit()
                .frame(height: 400)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .contentShape(.rect)
                .onTapGesture {
                    NotificationCenter.default.post(name: .quickInputResignFocus, object: nil)
                }
            
            if !viewModel.faces.isEmpty {
                FaceCarouselView(viewModel: viewModel)
                    .padding(.bottom, 20)
            }
        }
        .frame(height: 400)
    }
    
    private func mapRawTextToFaces(_ raw: String) {
        var newFaces = viewModel.faces
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        for (i, part) in parts.enumerated() where i < newFaces.count {
            let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            newFaces[i].name = name.isEmpty ? nil : name
        }
        viewModel.faces = newFaces
    }
    
    private var photoDetailsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Photo Details")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    showCropper = true
                } label: {
                    Label("Crop", systemImage: "crop")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            
            DatePicker("Date", selection: $detectedDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
            
            TextField("Group (optional)", text: $globalGroupText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var instructionSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.cursor")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text("Type names below separated by commas")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Text("Example: Alma, , Karen, Daniel")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            
            Text("Empty spots skip that face")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var noFacesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No faces detected")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("Tap back to return, or crop the image to try again")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var readyToAddFaces: [FaceDetectionViewModel.DetectedFace] {
        viewModel.faces.filter { !($0.name ?? "").isEmpty }
    }
    
    private func saveAll() {
        guard !readyToAddFaces.isEmpty else { return }
        
        let trimmed = globalGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag: Tag? = trimmed.isEmpty ? nil : Tag.fetchOrCreate(named: trimmed, in: modelContext)
        
        for face in readyToAddFaces {
            let name = face.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            
            let data = face.image.jpegData(compressionQuality: 0.92) ?? Data()
            let contact = Contact(
                name: name,
                summary: "",
                isMetLongAgo: false,
                timestamp: detectedDate,
                notes: [],
                tags: tag == nil ? [] : [tag!],
                photo: data,
                group: "",
                cropOffsetX: 0,
                cropOffsetY: 0,
                cropScale: 1.0
            )
            modelContext.insert(contact)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("❌ Save failed: \(error)")
        }
        
        dismiss()
    }
}

struct FaceCarouselView: View {
    @ObservedObject var viewModel: FaceDetectionViewModel
    @State private var selectedIndex: Int?
    
    private var faces: [FaceDetectionViewModel.DetectedFace] { viewModel.faces }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(faces.indices, id: \.self) { index in
                        VStack(spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                Image(uiImage: faces[index].image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                selectedIndex == index ? Color.accentColor : Color.white.opacity(0.5),
                                                lineWidth: selectedIndex == index ? 3 : 2
                                            )
                                    }
                                
                                if (faces[index].name ?? "").isEmpty {
                                    Image(systemName: "questionmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Color.white, Color.yellow)
                                        .font(.title3)
                                } else {
                                    Image(systemName: "checkmark.seal.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Color.white, Color.green)
                                        .font(.title3)
                                }
                            }
                            
                            Text(faces[index].name ?? "Unnamed")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .frame(width: 80)
                        }
                        .onTapGesture {
                            selectedIndex = index
                            withAnimation {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(
                Color.black.opacity(0.5)
                    .blur(radius: 10)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12)
            .onChange(of: selectedIndex) { oldValue, newValue in
                if let newValue {
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }
}

final class FaceDetectionViewModel: ObservableObject {
    struct DetectedFace: Identifiable {
        let id = UUID()
        let image: UIImage
        var name: String?
    }
    
    @Published var faces: [DetectedFace] = []
    @Published var isDetecting = false
    var faceObservations: [VNFaceObservation] = []
    
    @MainActor
    func detectFaces(in image: UIImage) async {
        guard let cgImage = image.cgImage else { return }
        
        isDetecting = true
        faces.removeAll()
        faceObservations.removeAll()
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        
        do {
            try handler.perform([request])
            
            if let observations = request.results as? [VNFaceObservation] {
                faceObservations = observations
                
                let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
                let fullRect = CGRect(origin: .zero, size: imageSize)
                
                for face in observations {
                    let bb = face.boundingBox
                    let scaleFactor: CGFloat = 1.8
                    
                    let scaledBox = CGRect(
                        x: bb.origin.x * imageSize.width - (bb.width * imageSize.width * (scaleFactor - 1)) / 2,
                        y: (1 - bb.origin.y - bb.height) * imageSize.height - (bb.height * imageSize.height * (scaleFactor - 1)) / 2,
                        width: bb.width * imageSize.width * scaleFactor,
                        height: bb.height * imageSize.height * scaleFactor
                    ).integral
                    
                    let clipped = scaledBox.intersection(fullRect)
                    if !clipped.isNull && !clipped.isEmpty {
                        if let cropped = cgImage.cropping(to: clipped) {
                            let faceImage = UIImage(cgImage: cropped)
                            faces.append(DetectedFace(image: faceImage, name: nil))
                        }
                    }
                }
            }
        } catch {
            print("Face detection failed: \(error)")
        }
        
        isDetecting = false
    }
}