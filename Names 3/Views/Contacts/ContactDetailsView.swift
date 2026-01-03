import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import Vision

struct ContactDetailsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var contact: Contact
    var isCreationFlow: Bool = false
    var onSave: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    @State var viewState = CGSize.zero

    @State private var showPhotosPicker = false

    @State private var selectedItem: PhotosPickerItem?

    @State private var showDatePicker = false
    @State private var showTagPicker = false
    @State private var showCropView = false
    @State private var isLoading = false
    
    @State private var showReplacePhotoAlert = false
    @State private var pendingPhotoData: Data?
    @State private var showFaceAssignment = false
    @State private var detectedFaces: [FaceAssignmentView.DetectedFaceInfo] = []
    @State private var pendingSourceImage: UIImage?

    @Query private var notes: [Note]

    @State private var noteText = ""
    @State private var stateNotes : [Note] = []
    @State private var CustomBackButtonAnimationValue = 40.0

    var image: UIImage { UIImage(data: contact.photo) ?? UIImage() }

    var body: some View {
        GeometryReader { g in
            ScrollView{
                ZStack(alignment: .bottom){
                    if image != UIImage() {
                        GeometryReader {
                            let size = $0.size
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size.width, height: size.height)
                                .overlay {
                                    LinearGradient(gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.2), .black.opacity(0.8)]), startPoint: .init(x: 0.5, y: 0.05), endPoint: .bottom)
                                }
                        }
                        .contentShape(.rect)
                        .frame(height: 400)
                        .clipped()
                    }

                    VStack{
                        HStack{
                            TextField(
                                "Name",
                                text: $contact.name ?? "",
                                prompt: Text("Name")
                                    .foregroundColor(image != UIImage() ? Color(.white.opacity(0.7)) : Color(uiColor: .placeholderText) ),
                                axis: .vertical
                            )
                            .font(.system(size: 36, weight: .bold))
                            .lineLimit(4)
                            .foregroundColor(image != UIImage() ? .white : .primary )

                            Image(systemName: "camera")
                                .font(.system(size: 18))
                                .padding(12)
                                .foregroundColor(image != UIImage() ? .blue.mix(with: .white, by: 0.3) : .blue)
                                .background( image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.7)) : AnyShapeStyle(Color(.blue.opacity(0.08))))
                                .background(image != UIImage() ? .black.opacity(0.2) : .clear)
                                .clipShape(Circle())
                                .onTapGesture { showPhotosPicker = true }
                                .padding(.leading, 4)

                            Group{
                                if !(contact.tags?.isEmpty ?? true) {
                                    Text((contact.tags ?? []).compactMap { $0.name }.sorted().joined(separator: ", "))
                                        .foregroundColor(image != UIImage() ? .white : Color(.secondaryLabel) )
                                        .font(.system(size: 15, weight: .medium))
                                        .padding(.vertical, 7)
                                        .padding(.bottom, 1)
                                        .padding(.horizontal, 13)
                                        .background(image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.6)) : AnyShapeStyle(Color(.quaternarySystemFill )))
                                        .cornerRadius(8)

                                } else {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 18))
                                        .padding(12)
                                        .foregroundColor(image != UIImage() ? .purple.mix(with: .white, by: 0.3) : .purple)
                                        .background( image != UIImage() ? AnyShapeStyle(.ultraThinMaterial.opacity(0.7)) : AnyShapeStyle(Color(.purple.opacity(0.08))))
                                        .clipShape(Circle())
                                        .padding(.leading, 4)
                                }
                            }
                            .onTapGesture { showTagPicker = true }
                        }
                        .padding(.horizontal)

                        TextField(
                            "",
                            text: $contact.summary ?? "",
                            prompt: Text("Main Note")
                                .foregroundColor(image != UIImage() ? Color(uiColor: .lightText).opacity(0.8) : Color(uiColor:.placeholderText)),
                            axis: .vertical
                        )
                        .lineLimit(2...)
                        .padding(10)
                        .foregroundStyle(image != UIImage() ? Color(uiColor: .lightText) : Color.primary)
                        .background(
                            BlurView(style: .regular)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        .padding(.horizontal).padding(.top, 12)
                        .onTapGesture {
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    viewState = value.translation
                                }
                        )

                        HStack{
                            Spacer()
                            Text(contact.timestamp, style: .date)
                                .foregroundColor(image != UIImage() ? .white : Color(UIColor.secondaryLabel))
                                .font(.system(size: 15))
                                .frame(alignment: .trailing)
                                .padding(.top, 4)
                                .padding(.trailing)
                                .padding(.trailing, 4)
                                .onTapGesture {
                                    showDatePicker = true
                                }
                                .padding(.bottom)
                                .onAppear{
                                }
                        }
                    }
                }

                HStack{
                    Text("Notes")
                        .font(.body.smallCaps())
                        .fontWeight(.light)
                        .foregroundStyle(.secondary)
                        .padding(.leading)
                    Spacer()
                }
                Button(action: {
                    let newNote = Note(content: "Test", creationDate: Date())
                    if contact.notes == nil { contact.notes = [] }
                    contact.notes?.append(newNote)
                    do {
                        try modelContext.save()
                    } catch {
                        print("Save failed: \(error)")
                    }
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Note")
                        Spacer()
                    }
                    .padding(.horizontal).padding(.vertical, 14)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .foregroundStyle(.blue)
                }
                .buttonStyle(PlainButtonStyle())

                List{
                    let array = (contact.notes ?? []).filter { $0.isArchived == false }
                    ForEach(array, id: \.self) { note in
                        Section{
                            NoteEditableRow(note: note, showContact: false)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        note.isArchived = true
                                        note.archivedDate = Date()
                                        do {
                                            try modelContext.save()
                                        } catch {
                                            print("Save failed: \(error)")
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                    } label: {
                                        Label("Edit Date", systemImage: "calendar")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .padding(.top, image != UIImage() ? 0 : 8 )
            .ignoresSafeArea(image != UIImage() ? .all : [])
            .background(Color(UIColor.systemGroupedBackground))
            .toolbar {
                if isCreationFlow {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            onCancel?() ?? dismiss()
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            do {
                                try modelContext.save()
                            } catch {
                                print("Save failed: \(error)")
                            }
                            onSave?()
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                            } label: {
                                Text("Duplicate")
                            }
                            Button {
                                contact.isArchived = true
                                contact.archivedDate = Date()
                                do {
                                    try modelContext.save()
                                } catch {
                                    print("Save failed: \(error)")
                                }
                                dismiss()
                            } label: {
                                Text("Delete")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            HStack {
                                HStack{
                                    Image(systemName: image != UIImage() ? "" : "chevron.backward")
                                    Text("Back")
                                        .fontWeight(image != UIImage() ? .medium : .regular)
                                }
                                .padding(.trailing, 8)
                            }
                            .padding(.leading, CustomBackButtonAnimationValue)
                            .onAppear{
                                withAnimation {
                                    CustomBackButtonAnimationValue = 0
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
        }
        .toolbarBackground(.hidden)
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItem, matching: .images)
        .sheet(isPresented: $showDatePicker) {
            CustomDatePicker(contact: contact)
        }
        .sheet(isPresented: $showTagPicker) {
            TagPickerView(mode: .contactToggle(contact: contact))
        }
        .fullScreenCover(isPresented: $showCropView){
            if let image = UIImage(data: contact.photo) {
                CropView(
                    image: image,
                    initialScale: CGFloat(contact.cropScale),
                    initialOffset: CGSize(width: CGFloat(contact.cropOffsetX), height: CGFloat(contact.cropOffsetY))
                ) { croppedImage, scale, offset in
                    updateCroppingParameters(croppedImage: croppedImage, scale: scale, offset: offset)
                }
            }
        }
        .sheet(isPresented: $showFaceAssignment) {
            if let sourceImage = pendingSourceImage {
                FaceAssignmentView(
                    sourceImage: sourceImage,
                    detectedFaces: detectedFaces,
                    targetContact: contact
                ) { assignedFaces in
                    handleMultipleFacesAssigned(assignedFaces)
                }
            }
        }
        .alert("Replace Photo?", isPresented: $showReplacePhotoAlert) {
            Button("Cancel", role: .cancel) {
                pendingPhotoData = nil
            }
            Button("Replace") {
                if let data = pendingPhotoData {
                    contact.photo = data
                    showCropView = true
                    do {
                        try modelContext.save()
                    } catch {
                        print("Save failed: \(error)")
                    }
                }
                pendingPhotoData = nil
            }
        } message: {
            Text("This contact already has a photo. Do you want to replace it?")
        }
        .overlay {
            if isLoading {
                LoadingOverlay(message: "Processing photo…")
            }
        }
        .onChange(of: selectedItem) {
            isLoading = true
            Task {
                await handlePhotoSelection()
                isLoading = false
            }
        }
    }

    func updateCroppingParameters(croppedImage: UIImage?, scale: CGFloat, offset: CGSize) {
        if let croppedImage = croppedImage {
            contact.photo = croppedImage.jpegData(compressionQuality: 1.0) ?? Data()
        }
        contact.cropScale = Float(scale)
        contact.cropOffsetX = Float(offset.width)
        contact.cropOffsetY = Float(offset.height)
        do {
            try modelContext.save()
        } catch {
            print("Save failed: \(error)")
        }
    }
    
    @MainActor
    private func handlePhotoSelection() async {
        guard let loaded = try? await selectedItem?.loadTransferable(type: Data.self),
              let selectedImage = UIImage(data: loaded) else {
            print("Failed to load image")
            return
        }
        
        let faces = await detectFaces(in: selectedImage)
        
        if faces.isEmpty {
            contact.photo = loaded
            showCropView = true
            do {
                try modelContext.save()
            } catch {
                print("Save failed: \(error)")
            }
            return
        }
        
        if faces.count == 1 {
            await handleSingleFace(faces[0], sourceImage: selectedImage, originalData: loaded)
        } else {
            pendingSourceImage = selectedImage
            detectedFaces = faces
            showFaceAssignment = true
        }
    }
    
    @MainActor
    private func handleSingleFace(_ face: FaceAssignmentView.DetectedFaceInfo, sourceImage: UIImage, originalData: Data) {
        let hasExistingPhoto = !contact.photo.isEmpty
        
        if hasExistingPhoto {
            pendingPhotoData = face.image.jpegData(compressionQuality: 0.92)
            showReplacePhotoAlert = true
        } else {
            contact.photo = face.image.jpegData(compressionQuality: 0.92) ?? Data()
            showCropView = true
            do {
                try modelContext.save()
            } catch {
                print("Save failed: \(error)")
            }
        }
    }
    
    private func handleMultipleFacesAssigned(_ assignedFaces: [FaceAssignmentView.AssignedFace]) {
        for assignedFace in assignedFaces {
            let name = assignedFace.name
            
            let fetchDescriptor = FetchDescriptor<Contact>(
                predicate: #Predicate<Contact> { contact in
                    contact.name == name && contact.isArchived == false
                }
            )
            
            if let existingContact = try? modelContext.fetch(fetchDescriptor).first {
                let hasExistingPhoto = !existingContact.photo.isEmpty
                if !hasExistingPhoto {
                    existingContact.photo = assignedFace.image.jpegData(compressionQuality: 0.92) ?? Data()
                }
            } else {
                let newContact = Contact(
                    name: name,
                    timestamp: contact.timestamp,
                    photo: assignedFace.image.jpegData(compressionQuality: 0.92) ?? Data()
                )
                modelContext.insert(newContact)
            }
        }
        
        do {
            try modelContext.save()
        } catch {
            print("Save failed: \(error)")
        }
    }
    
    private func detectFaces(in image: UIImage) async -> [FaceAssignmentView.DetectedFaceInfo] {
        guard let cgImage = image.cgImage else { return [] }
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        
        do {
            try handler.perform([request])
            
            if let observations = request.results as? [VNFaceObservation] {
                let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
                let fullRect = CGRect(origin: .zero, size: imageSize)
                
                var detectedFaces: [FaceAssignmentView.DetectedFaceInfo] = []
                
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
                            detectedFaces.append(FaceAssignmentView.DetectedFaceInfo(
                                image: faceImage,
                                boundingBox: clipped
                            ))
                        }
                    }
                }
                
                return detectedFaces
            }
        } catch {
            print("Face detection failed: \(error)")
        }
        
        return []
    }
}