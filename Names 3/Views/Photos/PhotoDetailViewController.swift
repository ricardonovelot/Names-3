import UIKit
import Photos
import SwiftUI
import Vision
import SwiftData

final class PhotoDetailViewController: UIViewController {
    
    let imageView = UIImageView()
    let scrollView = UIScrollView()
    
    private let image: UIImage
    private let date: Date?
    private let contactsContext: ModelContext
    private let onComplete: ((UIImage, Date?) -> Void)?
    
    private var hostingController: UIHostingController<PhotoDetailContentView>?
    
    init(image: UIImage, date: Date?, contactsContext: ModelContext, onComplete: ((UIImage, Date?) -> Void)? = nil) {
        self.image = image
        self.date = date
        self.contactsContext = contactsContext
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalPresentationCapturesStatusBarAppearance = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupGestures()
        setupSwiftUIContent()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showContent()
    }
    
    private func setupViews() {
        view.backgroundColor = .black
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)
        
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }
    
    private func setupSwiftUIContent() {
        let contentView = PhotoDetailContentView(
            image: image,
            date: date ?? Date(),
            contactsContext: contactsContext,
            onDismiss: { [weak self] in
                print("🔵 [PhotoDetail] onDismiss called")
                self?.dismissView()
            },
            onComplete: { [weak self] finalImage, finalDate in
                print("✅ [PhotoDetail] onComplete called")
                self?.onComplete?(finalImage, finalDate)
                self?.dismissView()
            }
        )
        
        let hosting = UIHostingController(rootView: contentView)
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.alpha = 0
        
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor)
        ])
        
        self.hostingController = hosting
    }
    
    private func showContent() {
        UIView.animate(
            withDuration: 0.4,
            delay: 0.1,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.5
        ) {
            self.hostingController?.view.alpha = 1
        }
    }
    
    private func dismissView() {
        print("🔵 [PhotoDetail] dismissView called")
        
        // Reset any transforms before dismissing
        view.transform = .identity
        view.alpha = 1.0
        
        dismiss(animated: true) {
            print("✅ [PhotoDetail] Dismiss animation completed")
        }
    }
    
    private func setupGestures() {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let progress = abs(translation.y) / view.bounds.height
        
        switch gesture.state {
        case .began:
            // Only allow pan to dismiss if not zoomed
            if scrollView.zoomScale != 1.0 {
                gesture.isEnabled = false
                gesture.isEnabled = true
            }
            
        case .changed:
            guard scrollView.zoomScale == 1.0 else { return }
            
            let scale = 1.0 - (progress * 0.3)
            view.transform = CGAffineTransform(scaleX: scale, y: scale)
                .translatedBy(x: 0, y: translation.y / scale)
            view.alpha = 1.0 - (progress * 0.5)
            
        case .ended, .cancelled:
            if progress > 0.3 || gesture.velocity(in: view).y > 1000 {
                print("🔵 [PhotoDetail] Pan gesture triggered dismiss")
                dismissView()
            } else {
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.8,
                    initialSpringVelocity: 0
                ) {
                    self.view.transform = .identity
                    self.view.alpha = 1.0
                }
            }
            
        default:
            break
        }
    }
}

extension PhotoDetailViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if scrollView.zoomScale > 1.0 {
            UIView.animate(withDuration: 0.2) {
                self.hostingController?.view.alpha = 0
            }
        } else {
            UIView.animate(withDuration: 0.2) {
                self.hostingController?.view.alpha = 1
            }
        }
    }
}

extension PhotoDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: view)
            return abs(velocity.y) > abs(velocity.x) && scrollView.zoomScale == 1.0
        }
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

// MARK: - SwiftUI Content View

struct PhotoDetailContentView: View {
    let image: UIImage
    @State private var currentImage: UIImage
    @State private var detectedDate: Date
    let contactsContext: ModelContext
    let onDismiss: () -> Void
    let onComplete: (UIImage, Date) -> Void
    
    @StateObject private var viewModel = FaceDetectionViewModel()
    @State private var globalGroupText: String = ""
    @State private var showCropper = false
    @State private var selectedFaceIndex: Int = 0
    @State private var currentNameText: String = ""
    
    init(image: UIImage, date: Date, contactsContext: ModelContext, onDismiss: @escaping () -> Void, onComplete: @escaping (UIImage, Date) -> Void) {
        self.image = image
        self._currentImage = State(initialValue: image)
        self._detectedDate = State(initialValue: date)
        self.contactsContext = contactsContext
        self.onDismiss = onDismiss
        self.onComplete = onComplete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            contentCard
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .onAppear {
            Task {
                await viewModel.detectFaces(in: image)
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
    }
    
    private var contentCard: some View {
        VStack(spacing: 0) {
            topToolbar
            
            ScrollView {
                VStack(spacing: 20) {
                    settingsSection
                    
                    if !viewModel.faces.isEmpty {
                        facesCarousel
                        nameInputSection
                        readyToAddSection
                    } else if !viewModel.isDetecting {
                        noFacesView
                    }
                }
                .padding()
            }
            .frame(maxHeight: 500)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        }
        .padding()
        .shadow(color: .black.opacity(0.3), radius: 20, y: -5)
    }
    
    private var topToolbar: some View {
        HStack {
            Button {
                print("🔵 [PhotoDetailContent] Dismiss button tapped")
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            
            Spacer()
            
            Button {
                showCropper = true
            } label: {
                Image(systemName: "crop")
                    .font(.title3)
            }
            
            Button {
                print("🔵 [PhotoDetailContent] Save button tapped")
                saveAll()
            } label: {
                Text("Save")
                    .fontWeight(.semibold)
            }
            .disabled(readyToAddFaces.isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    private var settingsSection: some View {
        VStack(spacing: 16) {
            DatePicker("Date", selection: $detectedDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
            
            TextField("Group (optional)", text: $globalGroupText)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
        }
    }
    
    private var noFacesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No faces detected")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Text("You can still save this photo without detected faces")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
    }
    
    private var facesCarousel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detected Faces")
                .font(.headline)
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.faces.indices, id: \.self) { index in
                            VStack(spacing: 8) {
                                ZStack(alignment: .bottomTrailing) {
                                    Image(uiImage: viewModel.faces[index].image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                        .overlay {
                                            Circle()
                                                .strokeBorder(
                                                    selectedFaceIndex == index ? Color.accentColor : Color.clear,
                                                    lineWidth: 3
                                                )
                                        }
                                    
                                    if (viewModel.faces[index].name ?? "").isEmpty {
                                        Image(systemName: "questionmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Color.white, Color.accentColor)
                                            .font(.title3)
                                    } else {
                                        Image(systemName: "checkmark.seal.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Color.white, Color.green)
                                            .font(.title3)
                                    }
                                }
                                
                                Text(viewModel.faces[index].name ?? "Unnamed")
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 80)
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
                }
                .onChange(of: selectedFaceIndex) { oldValue, newValue in
                    withAnimation {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }
    
    private var nameInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name for Selected Face")
                .font(.headline)
            
            HStack {
                TextField("Type a name and press return", text: $currentNameText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.words)
                    .onSubmit {
                        applyCurrentName()
                    }
                
                Button {
                    applyCurrentName()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
                .disabled(currentNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    
    private var readyToAddSection: some View {
        Group {
            if !readyToAddFaces.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ready to Add (\(readyToAddFaces.count))")
                        .font(.headline)
                    
                    ForEach(readyToAddFaces.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            Image(uiImage: readyToAddFaces[index].image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                            
                            Text(readyToAddFaces[index].name ?? "")
                                .font(.body)
                            
                            Spacer()
                            
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    private var readyToAddFaces: [FaceDetectionViewModel.DetectedFace] {
        viewModel.faces.filter { !($0.name ?? "").isEmpty }
    }
    
    private func applyCurrentName() {
        let trimmed = currentNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if selectedFaceIndex >= 0 && selectedFaceIndex < viewModel.faces.count {
            viewModel.faces[selectedFaceIndex].name = trimmed
        }
        
        currentNameText = ""
        
        if selectedFaceIndex < viewModel.faces.count - 1 {
            selectedFaceIndex += 1
        }
    }
    
    private func saveAll() {
        let trimmed = globalGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag: Tag? = trimmed.isEmpty ? nil : Tag.fetchOrCreate(named: trimmed, in: contactsContext)
        
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
            contactsContext.insert(contact)
        }
        
        do {
            try contactsContext.save()
            print("✅ [PhotoDetailContent] Contacts saved successfully")
        } catch {
            print("❌ [PhotoDetailContent] Save failed: \(error)")
        }
        
        onComplete(currentImage, detectedDate)
    }
}

// MARK: - Face Detection ViewModel

final class FaceDetectionViewModel: ObservableObject {
    struct DetectedFace: Identifiable {
        let id = UUID()
        let image: UIImage
        var name: String?
    }
    
    @Published var faces: [DetectedFace] = []
    @Published var isDetecting = false
    
    @MainActor
    func detectFaces(in image: UIImage) async {
        guard let cgImage = image.cgImage else { return }
        
        isDetecting = true
        faces.removeAll()
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        
        do {
            try handler.perform([request])
            
            if let observations = request.results as? [VNFaceObservation] {
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