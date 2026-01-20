import UIKit
import SwiftData
import Photos
import Vision

protocol WelcomeFaceNamingViewControllerDelegate: AnyObject {
    func welcomeFaceNamingViewControllerDidFinish(_ controller: WelcomeFaceNamingViewController)
}

final class WelcomeFaceNamingViewController: UIViewController {
    
    weak var delegate: WelcomeFaceNamingViewControllerDelegate?
    
    private let photosWithFaces: [(image: UIImage, date: Date, asset: PHAsset)]
    private let modelContext: ModelContext
    
    private var currentPhotoIndex = 0
    private var detectedFaces: [DetectedFaceInfo] = []
    private var faceAssignments: [String] = []
    private var totalFacesSaved = 0
    
    private struct DetectedFaceInfo {
        let image: UIImage
        let boundingBox: CGRect
    }
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Welcome! Let's Name Some Faces"
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.textColor = .label
        label.numberOfLines = 0
        return label
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "We found faces in your recent photos. Let's start naming them!"
        label.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()
    
    private lazy var photoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 16
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.secondarySystemBackground
        return imageView
    }()
    
    private lazy var facesCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(FaceCell.self, forCellWithReuseIdentifier: FaceCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        return collectionView
    }()
    
    private lazy var nameTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Type a name and press return"
        textField.font = UIFont.systemFont(ofSize: 17)
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.returnKeyType = .done
        textField.delegate = self
        textField.backgroundColor = UIColor.secondarySystemGroupedBackground
        return textField
    }()
    
    private lazy var skipPhotoButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Skip Photo", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        button.addTarget(self, action: #selector(skipPhotoTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var doneButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Done", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        button.contentEdgeInsets = UIEdgeInsets(top: 16, left: 32, bottom: 16, right: 32)
        button.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var progressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        label.textAlignment = .center
        label.textColor = .tertiaryLabel
        return label
    }()
    
    private var currentFaceIndex = 0
    
    init(photosWithFaces: [(image: UIImage, date: Date, asset: PHAsset)], modelContext: ModelContext) {
        self.photosWithFaces = photosWithFaces
        self.modelContext = modelContext
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        loadCurrentPhoto()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        nameTextField.becomeFirstResponder()
    }
    
    private func setupView() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(photoImageView)
        view.addSubview(facesCollectionView)
        view.addSubview(nameTextField)
        view.addSubview(skipPhotoButton)
        view.addSubview(doneButton)
        view.addSubview(progressLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            
            photoImageView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            photoImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            photoImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            photoImageView.heightAnchor.constraint(equalToConstant: 280),
            
            facesCollectionView.topAnchor.constraint(equalTo: photoImageView.bottomAnchor, constant: 20),
            facesCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            facesCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            facesCollectionView.heightAnchor.constraint(equalToConstant: 120),
            
            nameTextField.topAnchor.constraint(equalTo: facesCollectionView.bottomAnchor, constant: 20),
            nameTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            nameTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            nameTextField.heightAnchor.constraint(equalToConstant: 50),
            
            skipPhotoButton.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: 12),
            skipPhotoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            progressLabel.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -12),
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
    
    private func loadCurrentPhoto() {
        guard currentPhotoIndex < photosWithFaces.count else {
            finish()
            return
        }
        
        let photoData = photosWithFaces[currentPhotoIndex]
        photoImageView.image = photoData.image
        
        updateProgressLabel()
        
        Task {
            await detectFacesInCurrentPhoto(photoData.image)
            await MainActor.run {
                facesCollectionView.reloadData()
                if !detectedFaces.isEmpty {
                    currentFaceIndex = 0
                    facesCollectionView.selectItem(
                        at: IndexPath(item: 0, section: 0),
                        animated: false,
                        scrollPosition: .centeredHorizontally
                    )
                }
            }
        }
    }
    
    private func detectFacesInCurrentPhoto(_ image: UIImage) async {
        guard let cgImage = image.cgImage else {
            detectedFaces = []
            faceAssignments = []
            return
        }
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            let observations = (request.results as? [VNFaceObservation]) ?? []
            
            let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            let fullRect = CGRect(origin: .zero, size: imageSize)
            
            var faces: [DetectedFaceInfo] = []
            
            for observation in observations {
                let boundingBox = observation.boundingBox
                let scaleFactor: CGFloat = 1.8
                
                let scaledBox = CGRect(
                    x: boundingBox.origin.x * imageSize.width - (boundingBox.width * imageSize.width * (scaleFactor - 1)) / 2,
                    y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height - (boundingBox.height * imageSize.height * (scaleFactor - 1)) / 2,
                    width: boundingBox.width * imageSize.width * scaleFactor,
                    height: boundingBox.height * imageSize.height * scaleFactor
                ).integral
                
                let clipped = scaledBox.intersection(fullRect)
                
                if !clipped.isNull && !clipped.isEmpty,
                   let croppedCGImage = cgImage.cropping(to: clipped) {
                    let faceImage = UIImage(cgImage: croppedCGImage)
                    faces.append(DetectedFaceInfo(image: faceImage, boundingBox: clipped))
                }
            }
            
            await MainActor.run {
                self.detectedFaces = faces
                self.faceAssignments = Array(repeating: "", count: faces.count)
            }
        } catch {
            print("❌ Face detection error: \(error)")
            await MainActor.run {
                self.detectedFaces = []
                self.faceAssignments = []
            }
        }
    }
    
    private func updateProgressLabel() {
        let namedCount = faceAssignments.filter { !$0.isEmpty }.count
        progressLabel.text = "Photo \(currentPhotoIndex + 1) of \(photosWithFaces.count) • \(totalFacesSaved) faces named so far"
    }
    
    @objc private func skipPhotoTapped() {
        moveToNextPhoto()
    }
    
    @objc private func doneTapped() {
        finish()
    }
    
    private func moveToNextPhoto() {
        saveCurrentFaces()
        currentPhotoIndex += 1
        currentFaceIndex = 0
        nameTextField.text = ""
        loadCurrentPhoto()
    }
    
    private func saveCurrentFaces() {
        guard currentPhotoIndex < photosWithFaces.count else { return }
        
        let photoData = photosWithFaces[currentPhotoIndex]
        
        for (index, name) in faceAssignments.enumerated() {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard index < detectedFaces.count else { continue }
            
            let faceInfo = detectedFaces[index]
            let data = faceInfo.image.jpegData(compressionQuality: 0.92) ?? Data()
            
            let contact = Contact(
                name: trimmed,
                summary: "",
                isMetLongAgo: false,
                timestamp: photoData.date,
                notes: [],
                tags: [],
                photo: data,
                group: "",
                cropOffsetX: 0,
                cropOffsetY: 0,
                cropScale: 1.0
            )
            
            modelContext.insert(contact)
            totalFacesSaved += 1
        }
        
        do {
            try modelContext.save()
            print("✅ Saved \(faceAssignments.filter { !$0.isEmpty }.count) faces from photo \(currentPhotoIndex + 1)")
        } catch {
            print("❌ Failed to save faces: \(error)")
        }
    }
    
    private func finish() {
        saveCurrentFaces()
        
        let message: String
        if totalFacesSaved > 0 {
            message = "Great! You named \(totalFacesSaved) \(totalFacesSaved == 1 ? "face" : "faces"). You can add more anytime from the photo library."
        } else {
            message = "No problem! You can name faces anytime from the photo library."
        }
        
        let alert = UIAlertController(
            title: "All Set!",
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Get Started", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.welcomeFaceNamingViewControllerDidFinish(self)
        })
        
        present(alert, animated: true)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }
}

extension WelcomeFaceNamingViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return detectedFaces.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FaceCell.reuseIdentifier, for: indexPath) as! FaceCell
        
        let faceInfo = detectedFaces[indexPath.item]
        let assignedName = faceAssignments[indexPath.item]
        let isNamed = !assignedName.isEmpty
        
        cell.configure(with: faceInfo.image, name: assignedName, isNamed: isNamed)
        
        return cell
    }
}

extension WelcomeFaceNamingViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        currentFaceIndex = indexPath.item
        nameTextField.text = faceAssignments[currentFaceIndex]
        nameTextField.becomeFirstResponder()
    }
}

extension WelcomeFaceNamingViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 90, height: 120)
    }
}

extension WelcomeFaceNamingViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let name = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if !name.isEmpty && currentFaceIndex < faceAssignments.count {
            faceAssignments[currentFaceIndex] = name
            facesCollectionView.reloadItems(at: [IndexPath(item: currentFaceIndex, section: 0)])
            updateProgressLabel()
        }
        
        if currentFaceIndex < detectedFaces.count - 1 {
            currentFaceIndex += 1
            textField.text = faceAssignments[currentFaceIndex]
            facesCollectionView.selectItem(
                at: IndexPath(item: currentFaceIndex, section: 0),
                animated: true,
                scrollPosition: .centeredHorizontally
            )
        } else {
            textField.text = ""
            moveToNextPhoto()
        }
        
        return false
    }
}

private final class FaceCell: UICollectionViewCell {
    static let reuseIdentifier = "FaceCell"
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 45
        imageView.layer.borderWidth = 2
        imageView.layer.borderColor = UIColor.clear.cgColor
        return imageView
    }()
    
    private let statusIndicator: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        return imageView
    }()
    
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 2
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.addSubview(imageView)
        contentView.addSubview(statusIndicator)
        contentView.addSubview(nameLabel)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 90),
            imageView.heightAnchor.constraint(equalToConstant: 90),
            
            statusIndicator.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            statusIndicator.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            statusIndicator.widthAnchor.constraint(equalToConstant: 24),
            statusIndicator.heightAnchor.constraint(equalToConstant: 24),
            
            nameLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }
    
    func configure(with image: UIImage, name: String, isNamed: Bool) {
        imageView.image = image
        nameLabel.text = name.isEmpty ? "Unnamed" : name
        nameLabel.textColor = name.isEmpty ? .tertiaryLabel : .label
        
        if isNamed {
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            statusIndicator.image = UIImage(systemName: "checkmark.seal.fill", withConfiguration: config)
            statusIndicator.tintColor = .systemGreen
        } else {
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
            statusIndicator.image = UIImage(systemName: "questionmark.circle.fill", withConfiguration: config)
            statusIndicator.tintColor = .systemYellow
        }
    }
    
    override var isSelected: Bool {
        didSet {
            imageView.layer.borderColor = isSelected ? UIColor.systemBlue.cgColor : UIColor.clear.cgColor
            imageView.layer.borderWidth = isSelected ? 3 : 2
        }
    }
}