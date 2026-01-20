import SwiftUI
import SwiftData
import PhotosUI
import Photos
import Vision
import ImageIO

struct BulkAddFacesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var batchContext
    let contactsContext: ModelContext

    let existingBatch: FaceBatch?

    @StateObject private var viewModel = ViewModel()

    @State private var batch: FaceBatch?
    @State private var globalGroupText: String = ""
    @State private var globalDate: Date = Date()
    @State private var showCropper = false

    private let initialImage: UIImage?
    private let initialDate: Date?
    @State private var seedApplied = false

    init(existingBatch: FaceBatch? = nil, contactsContext: ModelContext) {
        self.existingBatch = existingBatch
        self.contactsContext = contactsContext
        self.initialImage = nil
        self.initialDate = nil
    }

    init(existingBatch: FaceBatch? = nil, contactsContext: ModelContext, initialImage: UIImage?, initialDate: Date?) {
        self.existingBatch = existingBatch
        self.contactsContext = contactsContext
        self.initialImage = initialImage
        self.initialDate = initialDate
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Bulk Add")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            persistBatchMetaIfNeeded()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            viewModel.showPhotosPicker = true
                        } label: {
                            Image(systemName: "photo.on.rectangle.angled")
                        }
                        Button {
                            if currentImage != nil {
                                showCropper = true
                            }
                        } label: {
                            Image(systemName: "crop")
                        }
                        .disabled(currentImage == nil)
                        Button {
                            saveAll()
                        } label: {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                        .disabled(readyToAddFaces.isEmpty)
                    }
                }
        }
        .onAppear { preloadIfExistingBatch() }
        .photosPicker(isPresented: $viewModel.showPhotosPicker, selection: $viewModel.selectedItem)
        .task(id: viewModel.selectedItem) { await handleNewPickerSelection() }
        .onChange(of: viewModel.imageItem) { _, _ in
            Task {
                if (batch?.faces?.isEmpty ?? true) {
                    await viewModel.detectFaces()
                    await persistFacesAfterDetection()
                }
            }
        }
        .fullScreenCover(isPresented: $showCropper) {
            if let img = currentImage {
                SimpleCropView(
                    image: img,
                    initialScale: 1.0,
                    initialOffset: .zero
                ) { cropped, scale, offset in
                    if let cropped {
                        viewModel.imageItem = cropped
                        if let b = batch {
                            b.image = downscaleJPEGData(image: cropped, maxDimension: 2400, quality: 0.9)
                            b.faces = []
                            do {
                                try batchContext.save()
                            } catch {
                                print("Failed to save cropped batch image: \(error)")
                            }
                        }
                    }
                    showCropper = false
                }
            }
        }
    }

    // MARK: - Subviews

    private var content: some View {
        VStack(spacing: 0) {
            List {
                applyAllSection
                imageArea
                if !viewModel.faces.isEmpty {
                    facesCarouselSection
                    nameFieldSection
                    readyToAddSection
                }
            }
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        viewModel.handleDragGesture(value: value)
                    }
            )
        }
    }

    private var applyAllSection: some View {
        Section("Apply to all") {
            DatePicker("Date", selection: $globalDate, in: ...Date(), displayedComponents: .date)
            HStack {
                TextField("Group (optional)", text: $globalGroupText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)
            }
        }
    }

    private var imageArea: some View {
        ZStack(alignment: .bottom) {
            if let data = batch?.image, let image = UIImage(data: data), image != UIImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if viewModel.imageItem != UIImage() {
                Image(uiImage: viewModel.imageItem)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Pick a photo to detect faces")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .listRowInsets(EdgeInsets())
    }

    private var facesCarouselSection: some View {
        Section("Faces") {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(viewModel.faces.indices, id: \.self) { index in
                            VStack(spacing: 6) {
                                ZStack(alignment: .bottomTrailing) {
                                    Image(uiImage: viewModel.faces[index].image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(Circle())
                                        .padding(3)
                                        .overlay(
                                            Circle()
                                                .stroke(viewModel.selectedFaceIndex == index ? Color.accentColor : Color.clear, lineWidth: 2)
                                        )

                                    if (viewModel.faces[index].assignedName ?? "").isEmpty {
                                        Image(systemName: "questionmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Color.white, Color.accentColor)
                                    } else if viewModel.faces[index].exported {
                                        Image(systemName: "checkmark.seal.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Color.white, Color.green)
                                    }
                                }
                                Text(viewModel.faces[index].assignedName ?? "")
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .onTapGesture {
                                viewModel.selectedFaceIndex = index
                                withAnimation {
                                    proxy.scrollTo(viewModel.selectedFaceIndex)
                                }
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var nameFieldSection: some View {
        Section {
            TextField(
                "Name for selected face",
                text: $viewModel.currentNameText,
                prompt: Text("Type a name and press return")
            )
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.words)
            .onSubmit {
                applyCurrentNameAndPersist()
            }
            .onChange(of: viewModel.currentNameText) { _, _ in }
        }
    }

    private var readyToAddSection: some View {
        Group {
            if !readyToAddFaces.isEmpty {
                Section("Ready to add") {
                    ForEach(readyToAddFaces, id: \.id) { face in
                        HStack {
                            Image(uiImage: face.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                            Text(face.assignedName ?? "")
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions and helpers

    private func preloadIfExistingBatch() {
        if let b = existingBatch {
            batch = b
            globalDate = b.date
            globalGroupText = b.groupName
            if let ui = UIImage(data: b.image) {
                viewModel.imageItem = ui
            }
            // load persisted faces in stable order and keep their UUID mapping
            let persisted = (b.faces ?? []).sorted { $0.order < $1.order }
            viewModel.faces = persisted.map { f in
                ViewModel.FaceEntry(
                    id: f.uuid,
                    image: UIImage(data: f.thumbnail) ?? UIImage(),
                    assignedName: f.assignedName.isEmpty ? nil : f.assignedName,
                    exported: f.exported
                )
            }
        }
        if !seedApplied {
            seedApplied = true
            if let d = initialDate, d <= Date() {
                globalDate = d
            }
            if let img = initialImage, img != UIImage() {
                viewModel.imageItem = img
                ensureBatchExistsIfNeeded()
                if let b = batch {
                    b.image = downscaleJPEGData(image: img, maxDimension: 2400, quality: 0.9)
                    do { try batchContext.save() } catch { print("Failed to save seeded batch image: \(error)") }
                }
                Task {
                    await viewModel.detectFaces()
                    await persistFacesAfterDetection()
                }
            }
        }
    }

    private func handleNewPickerSelection() async {
        guard let item = viewModel.selectedItem else { return }
        await viewModel.loadSelectedImage()
        if let date = await fetchPhotoDate(from: item) {
            if date <= Date() {
                globalDate = date
            }
        }
        await MainActor.run {
            ensureBatchExistsIfNeeded()
            if let img = currentImage, let b = batch {
                let data = downscaleJPEGData(image: img, maxDimension: 2400, quality: 0.9)
                b.image = data
                do {
                    try batchContext.save()
                } catch {
                    print("Failed to save batch after image selection: \(error)")
                }
            }
        }
    }

    private var currentImage: UIImage? {
        if let data = batch?.image, let image = UIImage(data: data), image != UIImage() {
            return image
        }
        return viewModel.imageItem == UIImage() ? nil : viewModel.imageItem
    }

    private var readyToAddFaces: [ViewModel.FaceEntry] {
        viewModel.faces.filter { (!($0.assignedName ?? "").isEmpty) && !$0.exported }
    }

    private func persistBatchMetaIfNeeded() {
        guard let b = batch else { return }
        b.date = globalDate
        b.groupName = globalGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try batchContext.save()
        } catch {
            print("Failed to save batch meta: \(error)")
        }
    }

    private func ensureBatchExistsIfNeeded() {
        if batch != nil { return }
        guard let img = currentImage else { return }
        let data = downscaleJPEGData(image: img, maxDimension: 2400, quality: 0.9)
        let new = FaceBatch(
            createdAt: Date(),
            date: globalDate,
            image: data,
            groupName: globalGroupText.trimmingCharacters(in: .whitespacesAndNewlines),
            faces: []
        )
        batchContext.insert(new)
        batch = new
        do {
            try batchContext.save()
        } catch {
            print("Failed creating batch: \(error)")
        }
    }

    private func persistFacesAfterDetection() async {
        await MainActor.run {
            ensureBatchExistsIfNeeded()
            guard let b = batch else { return }
            // Don't overwrite existing faces if already persisted (user may have named/exported some)
            if !(b.faces?.isEmpty ?? true) { return }

            // Create persistent faces with explicit order
            let newFaces: [FaceBatchFace] = viewModel.faces.enumerated().map { idx, fe in
                FaceBatchFace(
                    assignedName: fe.assignedName ?? "",
                    thumbnail: fe.image.jpegData(compressionQuality: 0.88) ?? Data(),
                    exported: false,
                    batch: b,
                    uuid: UUID(),
                    order: idx
                )
            }
            b.faces = newFaces

            // Map back UUIDs to the view model using order, not array index assumptions
            let persistedSorted = (b.faces ?? []).sorted { $0.order < $1.order }
            for (idx, pf) in persistedSorted.enumerated() {
                if idx < viewModel.faces.count {
                    viewModel.faces[idx].id = pf.uuid
                }
            }

            do {
                try batchContext.save()
            } catch {
                print("Failed saving detected faces: \(error)")
            }
        }
    }

    private func applyCurrentNameAndPersist() {
        let idx = viewModel.selectedFaceIndex
        let name = viewModel.currentNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if idx >= 0 && idx < viewModel.faces.count {
            viewModel.faces[idx].assignedName = name
        }
        viewModel.currentNameText = ""
        if let b = batch {
            // Update persisted face by stable UUID; fall back to order if needed
            if idx >= 0 && idx < viewModel.faces.count, let faceID = viewModel.faces[idx].id,
               let targetIndex = b.faces?.firstIndex(where: { $0.uuid == faceID }) {
                b.faces?[targetIndex].assignedName = name
            } else if idx >= 0 {
                // Fallback: update by order
                if let targetIndex = b.faces?.firstIndex(where: { $0.order == idx }) {
                    b.faces?[targetIndex].assignedName = name
                }
            }
            do {
                try batchContext.save()
            } catch {
                print("Failed saving name: \(error)")
            }
        }
        if idx < viewModel.faces.count - 1 {
            viewModel.selectedFaceIndex = idx + 1
        }
    }

    private func saveAll() {
        ensureBatchExistsIfNeeded()
        persistBatchMetaIfNeeded()

        guard let b = batch else {
            exportFacesFromViewModel()
            return
        }

        let trimmed = b.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? globalGroupText.trimmingCharacters(in: .whitespacesAndNewlines) : b.groupName
        let tagToApply: Tag? = trimmed.isEmpty ? nil : Tag.fetchOrCreate(named: trimmed, in: contactsContext, seedDate: b.date)

        let faces = b.faces ?? []
        for (idx, f) in faces.enumerated() {
            let name = f.assignedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && !f.exported {
                let thumbData = f.thumbnail
                let contact = Contact(
                    name: name,
                    summary: "",
                    isMetLongAgo: false,
                    timestamp: b.date,
                    notes: [],
                    tags: tagToApply == nil ? [] : [tagToApply!],
                    photo: thumbData,
                    group: "",
                    cropOffsetX: 0,
                    cropOffsetY: 0,
                    cropScale: 1.0
                )
                contactsContext.insert(contact)
                faces[idx].exported = true
            }
        }

        do {
            try contactsContext.save()
            try batchContext.save()
        } catch {
            print("Bulk save failed: \(error)")
        }

        dismiss()
    }

    private func exportFacesFromViewModel() {
        let trimmed = globalGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag: Tag? = trimmed.isEmpty ? nil : Tag.fetchOrCreate(named: trimmed, in: contactsContext)

        for face in readyToAddFaces {
            let name = face.assignedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            let data = face.image.jpegData(compressionQuality: 0.92) ?? Data()
            let contact = Contact(
                name: name,
                summary: "",
                isMetLongAgo: false,
                timestamp: globalDate,
                notes: [],
                tags: tag == nil ? [] : [tag!],
                photo: data,
                group: "",
                cropOffsetX: 0,
                cropOffsetY: 0,
                cropScale: 1.0
            )
            contactsContext.insert(contact)
        }

        do {
            try contactsContext.save()
        } catch {
            print("Bulk save (transient) failed: \(error)")
        }
    }
}

// MARK: - Helpers
private func fetchPhotoDate(from item: PhotosPickerItem) async -> Date? {
    if let id = item.itemIdentifier {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        if let asset = assets.firstObject, let creationDate = asset.creationDate {
            return creationDate
        }
    }
    if let data = try? await item.loadTransferable(type: Data.self) {
        return exifDate(from: data)
    }
    return nil
}

private func exifDate(from data: Data) -> Date? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }

    let exif = (props[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
    let tiff = (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]

    let candidates: [String?] = [
        exif[kCGImagePropertyExifDateTimeOriginal] as? String,
        exif[kCGImagePropertyExifDateTimeDigitized] as? String,
        tiff[kCGImagePropertyTIFFDateTime] as? String
    ]

    let fmts = [
        "yyyy:MM:dd HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy/MM/dd HH:mm:ss"
    ]
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for str in candidates.compactMap({ $0 }) {
        for f in fmts {
            formatter.dateFormat = f
            if let d = formatter.date(from: str) { return d }
        }
    }
    return nil
}

private func downscaleJPEGData(image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data {
    let width = image.size.width
    let height = image.size.height
    let maxSide = max(width, height)
    if maxSide <= maxDimension {
        return image.jpegData(compressionQuality: quality) ?? Data()
    }
    let scale = maxDimension / maxSide
    let newSize = CGSize(width: floor(width * scale), height: floor(height * scale))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
    let scaled = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }
    return scaled.jpegData(compressionQuality: quality) ?? Data()
}

extension BulkAddFacesView {
    final class ViewModel: ObservableObject {
        @Published var showPhotosPicker = false
        @Published var imageItem: UIImage = UIImage()
        @Published var selectedItem: PhotosPickerItem?

        struct FaceEntry: Identifiable, Hashable {
            // stable id comes from persistence; optional until saved
            var id: UUID?
            var image: UIImage
            var assignedName: String?
            var exported: Bool = false
        }

        @Published var faces: [FaceEntry] = []
        @Published var selectedFaceIndex: Int = 0
        @Published var currentNameText: String = ""

        var namedFaces: [FaceEntry] {
            faces.filter { !($0.assignedName ?? "").isEmpty }
        }

        @MainActor
        func loadSelectedImage() async {
            guard let pickerItem = selectedItem else { return }
            if let imageData = try? await pickerItem.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: imageData) {
                imageItem = uiImage
                selectedItem = nil
            }
        }

        func applyCurrentNameAndAdvance() {
            let trimmed = currentNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !faces.isEmpty, selectedFaceIndex >= 0, selectedFaceIndex < faces.count, !trimmed.isEmpty else { return }
            faces[selectedFaceIndex].assignedName = trimmed
        }

        func handleDragGesture(value: DragGesture.Value) {
            guard faces.indices.contains(selectedFaceIndex) else { return }
            if value.translation.width > 0 {
                if selectedFaceIndex < faces.count - 1 { selectedFaceIndex += 1 }
            } else {
                if selectedFaceIndex > 0 { selectedFaceIndex -= 1 }
            }
        }

        @MainActor
        private func resetForDetection() {
            faces.removeAll()
            selectedFaceIndex = 0
            currentNameText = ""
        }

        func detectFaces() async {
            guard let cgImage = imageItem.cgImage else {
                await MainActor.run { self.resetForDetection() }
                return
            }

            await MainActor.run { self.resetForDetection() }

            let fullRequest = VNDetectFaceRectanglesRequest()
            let fullHandler = VNImageRequestHandler(cgImage: cgImage)
            var observations: [VNFaceObservation] = []

            do {
                try fullHandler.perform([fullRequest])
                observations = (fullRequest.results as? [VNFaceObservation]) ?? []
            } catch {
                print("Face detection error: \(error)")
            }

            await MainActor.run {
                self.generateFaceThumbnails(from: observations, in: cgImage)
            }
        }

        @MainActor
        private func generateFaceThumbnails(from detected: [VNFaceObservation], in source: CGImage) {
            faces.removeAll()

            let imageSize = CGSize(width: CGFloat(source.width), height: CGFloat(source.height))
            let fullRect = CGRect(origin: .zero, size: imageSize)

            for face in detected {
                let bb = face.boundingBox
                let scaleFactor: CGFloat = 1.8

                var scaledBox = CGRect(
                    x: bb.origin.x * imageSize.width - (bb.width * imageSize.width * (scaleFactor - 1)) / 2,
                    y: (1 - bb.origin.y - bb.height) * imageSize.height - (bb.height * imageSize.height * (scaleFactor - 1)) / 2,
                    width: bb.width * imageSize.width * scaleFactor,
                    height: bb.height * imageSize.height * scaleFactor
                ).integral

                let clipped = scaledBox.intersection(fullRect)
                if clipped.isNull || clipped.isEmpty { continue }

                if let cgCropped = source.cropping(to: clipped) {
                    let thumb = UIImage(cgImage: cgCropped)
                    faces.append(FaceEntry(image: thumb, assignedName: nil, exported: false))
                }
            }

            if !faces.isEmpty {
                selectedFaceIndex = 0
                currentNameText = ""
            }
        }
    }
}