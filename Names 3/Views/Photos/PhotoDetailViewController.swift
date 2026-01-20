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
    
    private var saveButtons: [UIButton] = []
    
    private var saveButton: UIButton?
    
    private let image: UIImage
    private let date: Date?
    private let contactsContext: ModelContext
    private let onComplete: ((UIImage, Date?) -> Void)?
    
    var customBackAction: (() -> Void)?
    
    private var hostingController: UIHostingController<PhotoDetailContentView>?
    private var carouselHostingController: UIHostingController<PhotoFaceCarouselView>?
    private var quickInputHostingController: UIHostingController<AnyView>?
    private let navigationBar = UINavigationBar()
    private var singleAssignHostingController: UIHostingController<AssignFaceToContactView>?
    
    private let viewModel: FaceDetectionViewModel
    private var faceObservations: [VNFaceObservation] = []
    private var selectedFaceIndex: Int? {
        didSet {
            carouselHostingController?.rootView.updateSelectedIndex(selectedFaceIndex)
        }
    }
    
    private var quickInputBottomConstraint: NSLayoutConstraint!
    private var selectedContact: Contact? {
        didSet {
            print("🔵 [PhotoDetailVC] selectedContact didSet -> \(selectedContact?.name ?? "nil")")
            updateUIForSelectedContact()
        }
    }
    
    init(
        image: UIImage,
        date: Date?,
        contactsContext: ModelContext,
        faceDetectionViewModel: FaceDetectionViewModel,
        onComplete: ((UIImage, Date?) -> Void)? = nil
    ) {
        self.image = image
        self.date = date
        self.contactsContext = contactsContext
        self.viewModel = faceDetectionViewModel
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
        let backItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(backButtonTapped)
        )
        navItem.leftBarButtonItems = [backItem, makeGlassSaveBarButton()]
        navItem.rightBarButtonItem = makeGlassSaveBarButton()
        navItem.rightBarButtonItem?.isEnabled = false
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
        contentContainerView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
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
            onComplete: { [weak self] (finalImage: UIImage, finalDate: Date) in
                self?.onComplete?(finalImage, finalDate)
                self?.dismissView()
            },
            onReadyStateChanged: { [weak self] (hasReadyFaces: Bool) in
                if let navItem = self?.navigationBar.topItem {
                    navItem.rightBarButtonItem?.isEnabled = hasReadyFaces
                }
                self?.setSaveButtonEnabled(hasReadyFaces)
            },
            onFacesDetected: { [weak self] (observations: [VNFaceObservation], faces: [FaceDetectionViewModel.DetectedFace]) in
                self?.handleFacesDetected(observations, faces: faces)
            },
            onFaceNamed: { [weak self] (_ index: Int, _ named: Bool) in
                self?.carouselHostingController?.rootView.updateFaceNames()
            },
            onFaceSelected: { [weak self] (index: Int) in
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
        let selectedContactBinding = Binding<Contact?>(
            get: { [weak self] in self?.selectedContact },
            set: { [weak self] newValue in
                self?.selectedContact = newValue
            }
        )
        
        let quickInputView = QuickInputView(
            mode: .people,
            parsedContacts: parsedContacts,
            isQuickNotesActive: isQuickNotesActive,
            selectedContact: selectedContactBinding,
            onCameraTap: nil,
            allowQuickNoteCreation: false,
            onReturnOverride: {
                NotificationCenter.default.post(name: .photoDetailCommitRequested, object: nil)
            }
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
    
    private func makeGlassSaveBarButton() -> UIBarButtonItem {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.title = "Save"
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        button.configuration = config
        button.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
        
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.clipsToBounds = true
        blur.layer.cornerRadius = 16
        
        container.addSubview(blur)
        blur.contentView.addSubview(button)
        
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: container.topAnchor),
            blur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            button.topAnchor.constraint(equalTo: blur.contentView.topAnchor),
            button.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor)
        ])
        
        // Track for enabled/disabled sync
        saveButtons.append(button)
        setSaveButtonEnabled(false)
        
        return UIBarButtonItem(customView: container)
    }
    
    private func setSaveButtonEnabled(_ enabled: Bool) {
        for btn in saveButtons {
            btn.isEnabled = enabled
            btn.alpha = enabled ? 1.0 : 0.5
        }
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
        
        let carouselView = PhotoFaceCarouselView(
            viewModel: viewModel,
            onFaceSelected: { [weak self] index in
                guard let self = self else { return }
                if let contact = self.selectedContact, index >= 0, index < self.viewModel.faces.count {
                    let faceImage = self.viewModel.faces[index].image
                    contact.photo = faceImage.jpegData(compressionQuality: 0.92) ?? Data()
                    do {
                        try self.contactsContext.save()
                    } catch {
                        print("❌ Save failed: \(error)")
                    }
                    self.dismissView()
                } else {
                    self.selectedFaceIndex = index
                }
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
    
    private func updateUIForSelectedContact() {
        print("🔵 [PhotoDetailVC] updateUIForSelectedContact() contact: \(selectedContact?.name ?? "nil")")
        if let contact = selectedContact {
            presentSingleAssignView(with: contact)
        } else {
            dismissSingleAssignView()
        }
    }
    
    private func presentSingleAssignView(with contact: Contact) {
        print("🔵 [PhotoDetailVC] presentSingleAssignView for contact: \(contact.name)")
        hostingController?.view.isHidden = true
        carouselContainerView.isHidden = true
        quickInputContainerView.isHidden = true
        
        singleAssignHostingController?.view.removeFromSuperview()
        singleAssignHostingController?.removeFromParent()
        
        let assignView = AssignFaceToContactView(
            viewModel: viewModel,
            contact: contact,
            onSelectFace: { [weak self] index in
                guard let self = self else { return }
                guard index >= 0, index < self.viewModel.faces.count else { return }
                let faceImage = self.viewModel.faces[index].image
                contact.photo = faceImage.jpegData(compressionQuality: 0.92) ?? Data()
                do {
                    try self.contactsContext.save()
                } catch {
                    print("❌ Save failed: \(error)")
                }
                self.dismissView()
            },
            onCancel: { [weak self] in
                self?.selectedContact = nil
            }
        )
        
        let hosting = UIHostingController(rootView: assignView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
        
        addChild(hosting)
        contentContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: contentContainerView.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: contentContainerView.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor)
        ])
        
        singleAssignHostingController = hosting
    }
    
    private func dismissSingleAssignView() {
        singleAssignHostingController?.view.removeFromSuperview()
        singleAssignHostingController?.removeFromParent()
        singleAssignHostingController = nil
        
        hostingController?.view.isHidden = false
        carouselContainerView.isHidden = false
        quickInputContainerView.isHidden = false
    }
}

extension Notification.Name {
    static let photoDetailSaveRequested = Notification.Name("photoDetailSaveRequested")
    static let photoDetailCommitRequested = Notification.Name("photoDetailCommitRequested")
}

struct PhotoFaceCarouselView: View {
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
        .onReceive(NotificationCenter.default.publisher(for: .photoDetailCommitRequested)) { _ in
            commitReadyFacesWithoutDismissing()
        }
        .onReceive(NotificationCenter.default.publisher(for: .photoDetailSaveRequested)) { _ in
            saveAll()
        }
        .fullScreenCover(isPresented: $showCropper) {
            SimpleCropView(
                image: currentImage,
                initialScale: 1.0,
                initialOffset: .zero
            ) { cropped, scale, offset in
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
    
    private func commitReadyFacesWithoutDismissing() {
        let trimmed = globalGroupText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let tag: Tag? = trimmed.isEmpty ? nil : Tag.fetchOrCreate(named: trimmed, in: contactsContext, seedDate: detectedDate)
        
        var anySaved = false
        for i in viewModel.faces.indices {
            guard !viewModel.faces[i].isLocked else { continue }
            let name = viewModel.faces[i].name?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            let data = viewModel.faces[i].image.jpegData(compressionQuality: 0.92) ?? Data()
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
            viewModel.faces[i].isLocked = true
            anySaved = true
        }
        
        guard anySaved else { return }
        
        do {
            try contactsContext.save()
        } catch {
            print("❌ Save failed: \(error)")
        }
        
        // Keep names visible. Request focus so the user can continue typing for remaining faces.
        NotificationCenter.default.post(name: .quickInputRequestFocus, object: nil)
    }
    
    private func mapRawTextToFaces(_ raw: String) {
        var newFaces = viewModel.faces
        let parts = raw
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
        
        let unlocked = newFaces.indices.filter { !newFaces[$0].isLocked }
        var u = 0
        for part in parts {
            guard u < unlocked.count else { break }
            let idx = unlocked[u]
            let name = part
            let newName: String? = name.isEmpty ? nil : name
            if newFaces[idx].name != newName {
                newFaces[idx].name = newName
                onFaceNamed(idx, !(newName ?? "").isEmpty)
            }
            u += 1
        }
        while u < unlocked.count {
            let idx = unlocked[u]
            if newFaces[idx].name != nil {
                newFaces[idx].name = nil
                onFaceNamed(idx, false)
            }
            u += 1
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
        viewModel.faces.filter { !($0.name ?? "").isEmpty && !$0.isLocked }
    }
    
    private func saveAll() {
        guard !readyToAddFaces.isEmpty else { return }
        
        let trimmed = globalGroupText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let tag: Tag? = trimmed.isEmpty ? nil : Tag.fetchOrCreate(named: trimmed, in: contactsContext, seedDate: detectedDate)
        
        for i in viewModel.faces.indices {
            guard !viewModel.faces[i].isLocked else { continue }
            let name = viewModel.faces[i].name?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { continue }
            
            let data = viewModel.faces[i].image.jpegData(compressionQuality: 0.92) ?? Data()
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

struct AssignFaceToContactView: View {
    @ObservedObject var viewModel: FaceDetectionViewModel
    let contact: Contact
    let onSelectFace: (Int) -> Void
    let onCancel: () -> Void
    @State private var selectedIndex: Int?
    
    private var faces: [FaceDetectionViewModel.DetectedFace] { viewModel.faces }
    
    var body: some View {
        VStack(spacing: 16) {
            header
            
            if viewModel.isDetecting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding()
            } else if faces.isEmpty {
                noFacesView
            } else {
                facesGrid
            }
            
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.blue.opacity(0.15))
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Assign a face")
                    .font(.title2).bold()
                Text(contact.name ?? "")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", systemImage: "xmark") {
                onCancel()
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var noFacesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No faces detected")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Try cropping the image to focus on faces, then try again.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var facesGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 16)], spacing: 16) {
                ForEach(faces.indices, id: \.self) { index in
                    let face = faces[index]
                    Button {
                        selectedIndex = index
                        onSelectFace(index)
                    } label: {
                        VStack(spacing: 8) {
                            Image(uiImage: face.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 96, height: 96)
                                .clipShape(Circle())
                                .overlay {
                                    Circle()
                                        .strokeBorder(
                                            selectedIndex == index ? Color.accentColor : Color.gray.opacity(0.3),
                                            lineWidth: selectedIndex == index ? 4 : 2
                                        )
                                }
                            Text(face.name ?? "Face \(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: 120)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }
}