import UIKit
import Photos
import SwiftUI
import Vision
import SwiftData
import Combine

final class PhotoDetailViewController: UIViewController {
    
    private let imageContainerView = UIView()
    let imageView = UIImageView()
    private let carouselContainerView = UIView()
    private let contentContainerView = UIView()
    private let quickInputContainerView = UIView()
    
    private let image: UIImage
    private let date: Date?
    private let contactsContext: ModelContext
    private let onComplete: ((UIImage, Date?) -> Void)?
    
    var customBackAction: (() -> Void)?
    
    private var hostingController: UIHostingController<PhotoDetailContentView>?
    private var carouselHostingController: UIHostingController<FaceCarouselView>?
    private var quickInputHostingController: UIHostingController<AnyView>?
    private let navigationBar = UINavigationBar()
    
    private var viewModel = FaceDetectionViewModel()
    private var faceObservations: [VNFaceObservation] = []
    private var selectedFaceIndex: Int? {
        didSet {
            carouselHostingController?.rootView.updateSelectedIndex(selectedFaceIndex)
        }
    }
    
    private var quickInputBottomConstraint: NSLayoutConstraint!
    
    init(image: UIImage, date: Date?, contactsContext: ModelContext, onComplete: ((UIImage, Date?) -> Void)? = nil) {
        self.image = image
        self.date = date
        self.contactsContext = contactsContext
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupHeaderAndContent()
        setupSwiftUIContent()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("🎯 [PhotoDetailVC] viewDidAppear called - will request focus after 400ms")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            print("🎯 [PhotoDetailVC] Posting focus request now")
            NotificationCenter.default.post(name: .quickInputRequestFocus, object: nil)
        }
    }
    
    private func setupNavigationBar() {
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        navigationBar.isTranslucent = true
        
        let navItem = UINavigationItem(title: "")
        navItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backButtonTapped)
        )
        navItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(doneButtonTapped)
        )
        navigationBar.setItems([navItem], animated: false)
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor.clear
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        
        view.addSubview(navigationBar)
        
        NSLayoutConstraint.activate([
            navigationBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    private func setupHeaderAndContent() {
        view.backgroundColor = .clear
        
        imageContainerView.translatesAutoresizingMaskIntoConstraints = false
        imageContainerView.backgroundColor = .black
        imageContainerView.clipsToBounds = true
        view.addSubview(imageContainerView)
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageContainerView.addSubview(imageView)
        
        let tapToDismiss = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboardFromTap))
        tapToDismiss.cancelsTouchesInView = false
        imageContainerView.addGestureRecognizer(tapToDismiss)
        
        contentContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.backgroundColor = .clear
        view.addSubview(contentContainerView)
        
        carouselContainerView.translatesAutoresizingMaskIntoConstraints = false
        carouselContainerView.backgroundColor = .clear
        view.addSubview(carouselContainerView)
        
        quickInputContainerView.translatesAutoresizingMaskIntoConstraints = false
        quickInputContainerView.backgroundColor = .clear
        view.addSubview(quickInputContainerView)
        
        quickInputBottomConstraint = quickInputContainerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        
        NSLayoutConstraint.activate([
            imageContainerView.topAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            imageContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageContainerView.heightAnchor.constraint(equalToConstant: 350),
            
            imageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor),
            
            contentContainerView.topAnchor.constraint(equalTo: imageContainerView.bottomAnchor),
            contentContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainerView.bottomAnchor.constraint(equalTo: carouselContainerView.topAnchor),
            
            carouselContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            carouselContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            carouselContainerView.bottomAnchor.constraint(equalTo: quickInputContainerView.topAnchor),
            carouselContainerView.heightAnchor.constraint(equalToConstant: 100),
            
            quickInputContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            quickInputContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            quickInputBottomConstraint
        ])
        
        setupCarouselView()
    }
    
    private func setupSwiftUIContent() {
        let contentView = PhotoDetailContentView(
            image: image,
            date: date ?? Date(),
            contactsContext: contactsContext,
            viewModel: viewModel,
            onDismiss: { [weak self] in
                self?.dismissView()
            },
            onComplete: { [weak self] finalImage, finalDate in
                self?.onComplete?(finalImage, finalDate)
                self?.dismissView()
            },
            onReadyStateChanged: { [weak self] hasReadyFaces in
                if let navItem = self?.navigationBar.topItem {
                    navItem.rightBarButtonItem?.isEnabled = hasReadyFaces
                }
            },
            onFacesDetected: { [weak self] observations, faces in
                self?.handleFacesDetected(observations, faces: faces)
            },
            onFaceNamed: { [weak self] _, _ in
                self?.carouselHostingController?.rootView.updateFaceNames()
            },
            onFaceSelected: { [weak self] index in
                self?.selectedFaceIndex = index
            }
        )
        
        let hosting = UIHostingController(rootView: contentView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = UIColor.clear
        
        addChild(hosting)
        contentContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
        ])
        
        self.hostingController = hosting
        setupQuickInputView()
    }
    
    private func setupQuickInputView() {
        let parsedContacts = Binding<[Contact]>(
            get: { [] },
            set: { _ in }
        )
        let isQuickNotesActive = Binding<Bool>(
            get: { false },
            set: { _ in }
        )
        let selectedContact = Binding<Contact?>(
            get: { nil },
            set: { _ in }
        )
        
        let quickInputView = QuickInputView(
            mode: .people,
            parsedContacts: parsedContacts,
            isQuickNotesActive: isQuickNotesActive,
            selectedContact: selectedContact,
            onCameraTap: nil,
            allowQuickNoteCreation: false
        )
        
        let wrappedView = AnyView(
            quickInputView
                .onPreferenceChange(TotalQuickInputHeightKey.self) { [weak self] totalHeight in
                    self?.updateQuickInputOffset(totalHeight)
                }
        )
        
        let hosting = UIHostingController(rootView: wrappedView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = UIColor.clear
        
        addChild(hosting)
        quickInputContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: quickInputContainerView.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: quickInputContainerView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: quickInputContainerView.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: quickInputContainerView.bottomAnchor)
        ])
        
        self.quickInputHostingController = hosting
    }
    
    private func updateQuickInputOffset(_ totalHeight: CGFloat) {
        let baseHeight: CGFloat = 70
        let additionalHeight = max(0, totalHeight - baseHeight)
        
        quickInputBottomConstraint.constant = -additionalHeight
        
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.view.layoutIfNeeded()
        }
    }
    
    private func setupCarouselView() {
        carouselHostingController?.view.removeFromSuperview()
        carouselHostingController?.removeFromParent()
        
        let carouselView = FaceCarouselView(
            viewModel: viewModel,
            onFaceSelected: { [weak self] index in
                self?.selectedFaceIndex = index
            }
        )
        
        let hosting = UIHostingController(rootView: carouselView)
        hosting.view.backgroundColor = UIColor.clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        
        addChild(hosting)
        carouselContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: carouselContainerView.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: carouselContainerView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: carouselContainerView.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: carouselContainerView.bottomAnchor)
        ])
        
        self.carouselHostingController = hosting
        
        if let selectedIndex = selectedFaceIndex {
            carouselHostingController?.rootView.updateSelectedIndex(selectedIndex)
        }
    }
    
    private func handleFacesDetected(_ observations: [VNFaceObservation], faces: [FaceDetectionViewModel.DetectedFace]) {
        faceObservations = observations
        setupCarouselView()
    }
    
    @objc private func backButtonTapped() {
        if let customBackAction = customBackAction {
            customBackAction()
        } else {
            dismissView()
        }
    }
    
    @objc private func doneButtonTapped() {
        NotificationCenter.default.post(name: .photoDetailSaveRequested, object: nil)
    }
    
    @objc private func dismissKeyboardFromTap() {
        NotificationCenter.default.post(name: .quickInputResignFocus, object: nil)
        view.endEditing(true)
    }
    
    private func dismissView() {
        if let onComplete = onComplete {
        } else {
            dismiss(animated: true)
        }
    }
}

extension Notification.Name {
    static let photoDetailSaveRequested = Notification.Name("photoDetailSaveRequested")
}

struct FaceCarouselView: View {
    @ObservedObject var viewModel: FaceDetectionViewModel
    @State private var selectedIndex: Int?
    let onFaceSelected: (Int) -> Void
    
    private var faces: [FaceDetectionViewModel.DetectedFace] { viewModel.faces }
    
    var body: some View {
        if faces.isEmpty {
            Color.clear
                .frame(height: 0)
        } else {
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
                                                    selectedIndex == index ? Color.accentColor : Color.gray.opacity(0.3),
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
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .frame(width: 80)
                            }
                            .onTapGesture {
                                selectedIndex = index
                                onFaceSelected(index)
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
    
    func updateSelectedIndex(_ index: Int?) {
        selectedIndex = index
    }
    
    func updateFaceNames() {
    }
}

struct PhotoDetailContentView: View {
    let image: UIImage
    @State private var currentImage: UIImage
    @State private var detectedDate: Date
    let contactsContext: ModelContext
    @ObservedObject var viewModel: FaceDetectionViewModel
    let onDismiss: () -> Void
    let onComplete: (UIImage, Date) -> Void
    let onReadyStateChanged: (Bool) -> Void
    let onFacesDetected: ([VNFaceObservation], [FaceDetectionViewModel.DetectedFace]) -> Void
    let onFaceNamed: (Int, Bool) -> Void
    let onFaceSelected: (Int) -> Void
    
    @State private var globalGroupText: String = ""
    @State private var showCropper = false
    
    init(
        image: UIImage,
        date: Date,
        contactsContext: ModelContext,
        viewModel: FaceDetectionViewModel,
        onDismiss: @escaping () -> Void,
        onComplete: @escaping (UIImage, Date) -> Void,
        onReadyStateChanged: @escaping (Bool) -> Void,
        onFacesDetected: @escaping ([VNFaceObservation], [FaceDetectionViewModel.DetectedFace]) -> Void,
        onFaceNamed: @escaping (Int, Bool) -> Void,
        onFaceSelected: @escaping (Int) -> Void
    ) {
        self.image = image
        self._currentImage = State(initialValue: image)
        self._detectedDate = State(initialValue: date)
        self.contactsContext = contactsContext
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self.onComplete = onComplete
        self.onReadyStateChanged = onReadyStateChanged
        self.onFacesDetected = onFacesDetected
        self.onFaceNamed = onFaceNamed
        self.onFaceSelected = onFaceSelected
    }
    
    var body: some View {
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
        .onAppear {
            Task {
                await viewModel.detectFaces(in: image)
                onFacesDetected(viewModel.faceObservations, viewModel.faces)
            }
        }
        .onChange(of: readyToAddFaces.count) { oldValue, newValue in
            onReadyStateChanged(!readyToAddFaces.isEmpty)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickInputTextDidChange)) { output in
            if let text = output.userInfo?["text"] as? String {
                mapRawTextToFaces(text)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .photoDetailSaveRequested)) { _ in
            saveAll()
        }
        .fullScreenCover(isPresented: $showCropper) {
            SimpleCropView(image: currentImage) { cropped in
                if let cropped {
                    currentImage = cropped
                    Task {
                        await viewModel.detectFaces(in: cropped)
                        onFacesDetected(viewModel.faceObservations, viewModel.faces)
                    }
                }
                showCropper = false
            }
        }
    }
    
    private func mapRawTextToFaces(_ raw: String) {
        var newFaces = viewModel.faces
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        for (i, part) in parts.enumerated() where i < newFaces.count {
            let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                if newFaces[i].name != nil {
                    newFaces[i].name = nil
                    onFaceNamed(i, false)
                }
            } else {
                if newFaces[i].name != name {
                    newFaces[i].name = name
                    onFaceNamed(i, true)
                }
            }
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
            
            Text("Tap Done to go back, or crop the image to try again")
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
        } catch {
            print("❌ Save failed: \(error)")
        }
        
        onComplete(currentImage, detectedDate)
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