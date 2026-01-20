import UIKit
import SwiftData
import Photos
import Vision

protocol WelcomeFaceNamingViewControllerDelegate: AnyObject {
    func welcomeFaceNamingViewControllerDidFinish(_ controller: WelcomeFaceNamingViewController)
}

final class WelcomeFaceNamingViewController: UIViewController {
    
    weak var delegate: WelcomeFaceNamingViewControllerDelegate?
    
    private let prioritizedAssets: [PHAsset]
    private let modelContext: ModelContext
    private let imageManager = PHCachingImageManager()
    
    private var currentPhotoData: (image: UIImage, date: Date, asset: PHAsset)?
    private var detectedFaces: [DetectedFaceInfo] = []
    private var faceAssignments: [String] = []
    private var totalFacesSaved = 0
    private var totalPhotosProcessed = 0
    private var isLoadingNextPhoto = false
    
    private var recentlyShownFacePrints: [Data] = []
    private let maxRecentFaces = 30
    private let similarityThreshold: Float = 0.5
    
    private let prefetchCount = 5
    private let detectionTargetSize = CGSize(width: 1024, height: 1024)
    
    private var photoQueue: [PhotoCandidate] = []
    private var currentBatchIndex = 0
    private let batchSize = 30
    private var isPreprocessing = false
    
    private struct PhotoCandidate: Comparable {
        let asset: PHAsset
        let faceCount: Int
        let index: Int
        
        static func < (lhs: PhotoCandidate, rhs: PhotoCandidate) -> Bool {
            if lhs.faceCount != rhs.faceCount {
                if lhs.faceCount >= 2 && lhs.faceCount <= 5 {
                    if rhs.faceCount >= 2 && rhs.faceCount <= 5 {
                        return lhs.faceCount > rhs.faceCount
                    }
                    return true
                }
                if rhs.faceCount >= 2 && rhs.faceCount <= 5 {
                    return false
                }
                return lhs.faceCount > rhs.faceCount
            }
            return lhs.index < rhs.index
        }
    }
    
    private struct DetectedFaceInfo {
        let image: UIImage
        let boundingBox: CGRect
        let facePrint: Data?
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
        label.text = "We'll show you different people from your photos"
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
    
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
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
        label.numberOfLines = 2
        return label
    }()
    
    private var currentFaceIndex = 0
    
    init(prioritizedAssets: [PHAsset], modelContext: ModelContext) {
        self.prioritizedAssets = prioritizedAssets
        self.modelContext = modelContext
        super.init(nibName: nil, bundle: nil)
        
        imageManager.allowsCachingHighQualityImages = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        imageManager.stopCachingImagesForAllAssets()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        preprocessNextBatch()
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
        view.addSubview(loadingIndicator)
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
            
            loadingIndicator.centerXAnchor.constraint(equalTo: photoImageView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: photoImageView.centerYAnchor),
            
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
            progressLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            progressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
    
    private func preprocessNextBatch() {
        guard !isPreprocessing else { return }
        guard currentBatchIndex < prioritizedAssets.count else {
            if photoQueue.isEmpty {
                loadNextPhotoWithFaces()
            }
            return
        }
        
        isPreprocessing = true
        
        Task {
            let startIndex = currentBatchIndex
            let endIndex = min(startIndex + batchSize, prioritizedAssets.count)
            let batchAssets = Array(prioritizedAssets[startIndex..<endIndex])
            
            print("📦 Preprocessing batch \(startIndex)..<\(endIndex)")
            
            var candidates: [PhotoCandidate] = []
            
            for (offset, asset) in batchAssets.enumerated() {
                guard let image = await loadOptimizedImage(for: asset) else {
                    continue
                }
                
                let faceCount = await countFaces(in: image)
                
                if faceCount > 0 {
                    let candidate = PhotoCandidate(
                        asset: asset,
                        faceCount: faceCount,
                        index: startIndex + offset
                    )
                    candidates.append(candidate)
                }
            }
            
            await MainActor.run {
                self.photoQueue.append(contentsOf: candidates.sorted())
                self.currentBatchIndex = endIndex
                self.isPreprocessing = false
                
                print("✅ Batch complete. Queue now has \(self.photoQueue.count) photos")
                print("   2-5 faces: \(candidates.filter { $0.faceCount >= 2 && $0.faceCount <= 5 }.count)")
                print("   6+ faces: \(candidates.filter { $0.faceCount > 5 }.count)")
                print("   1 face: \(candidates.filter { $0.faceCount == 1 }.count)")
                
                if self.currentPhotoData == nil {
                    self.loadNextPhotoWithFaces()
                }
            }
        }
    }
    
    private func countFaces(in image: UIImage) async -> Int {
        guard let cgImage = image.cgImage else {
            return 0
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectFaceRectanglesRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try handler.perform([request])
                    let count = (request.results as? [VNFaceObservation])?.count ?? 0
                    continuation.resume(returning: count)
                } catch {
                    continuation.resume(returning: 0)
                }
            }
        }
    }
    
    private func requestOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        return options
    }
    
    private func loadNextPhotoWithFaces() {
        guard !isLoadingNextPhoto else { return }
        isLoadingNextPhoto = true
        
        loadingIndicator.startAnimating()
        detectedFaces = []
        faceAssignments = []
        facesCollectionView.reloadData()
        nameTextField.text = ""
        
        Task {
            while !photoQueue.isEmpty || currentBatchIndex < prioritizedAssets.count {
                if photoQueue.isEmpty {
                    await MainActor.run {
                        self.preprocessNextBatch()
                    }
                    
                    try? await Task.sleep(for: .milliseconds(100))
                    continue
                }
                
                let candidate = photoQueue.removeFirst()
                
                guard let image = await loadOptimizedImage(for: candidate.asset) else {
                    continue
                }
                
                let (hasFaces, hasNewFaces) = await detectAndCheckFaceDiversity(image)
                
                if hasFaces && hasNewFaces {
                    let date = candidate.asset.creationDate ?? Date()
                    await MainActor.run {
                        self.currentPhotoData = (image: image, date: date, asset: candidate.asset)
                        self.photoImageView.image = image
                        self.loadingIndicator.stopAnimating()
                        self.isLoadingNextPhoto = false
                        self.updateProgressLabel()
                        self.facesCollectionView.reloadData()
                        if !self.detectedFaces.isEmpty {
                            self.currentFaceIndex = 0
                            self.facesCollectionView.selectItem(
                                at: IndexPath(item: 0, section: 0),
                                animated: false,
                                scrollPosition: .centeredHorizontally
                            )
                        }
                        
                        if self.photoQueue.count < 10 && !self.isPreprocessing {
                            self.preprocessNextBatch()
                        }
                    }
                    return
                }
            }
            
            await MainActor.run {
                self.loadingIndicator.stopAnimating()
                self.isLoadingNextPhoto = false
                self.showNoMorePhotosAlert()
            }
        }
    }
    
    private func loadOptimizedImage(for asset: PHAsset) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: detectionTargetSize,
                contentMode: .aspectFit,
                options: requestOptions()
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    private func detectAndCheckFaceDiversity(_ image: UIImage) async -> (hasFaces: Bool, hasNewFaces: Bool) {
        guard let cgImage = image.cgImage else {
            return (false, false)
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let faceDetectionRequest = VNDetectFaceRectanglesRequest()
                let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try handler.perform([faceDetectionRequest, faceLandmarksRequest])
                    
                    guard let faceObservations = faceDetectionRequest.results as? [VNFaceObservation],
                          !faceObservations.isEmpty else {
                        continuation.resume(returning: (false, false))
                        return
                    }
                    
                    let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
                    let fullRect = CGRect(origin: .zero, size: imageSize)
                    
                    var faces: [DetectedFaceInfo] = []
                    var newFacePrints: [Data] = []
                    var hasAtLeastOneNewFace = false
                    
                    for observation in faceObservations {
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
                            
                            let facePrintData = self.generateFacePrint(for: observation, in: cgImage)
                            
                            let isNewFace = self.isFaceNew(facePrint: facePrintData)
                            if isNewFace {
                                hasAtLeastOneNewFace = true
                                if let fpData = facePrintData {
                                    newFacePrints.append(fpData)
                                }
                            }
                            
                            let faceImage = UIImage(cgImage: croppedCGImage)
                            faces.append(DetectedFaceInfo(
                                image: faceImage,
                                boundingBox: clipped,
                                facePrint: facePrintData
                            ))
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.detectedFaces = faces
                        self.faceAssignments = Array(repeating: "", count: faces.count)
                        
                        for fpData in newFacePrints {
                            self.recentlyShownFacePrints.append(fpData)
                        }
                        
                        if self.recentlyShownFacePrints.count > self.maxRecentFaces {
                            self.recentlyShownFacePrints.removeFirst(self.recentlyShownFacePrints.count - self.maxRecentFaces)
                        }
                        
                        continuation.resume(returning: (!faces.isEmpty, hasAtLeastOneNewFace))
                    }
                } catch {
                    print("❌ Face detection error: \(error)")
                    continuation.resume(returning: (false, false))
                }
            }
        }
    }
    
    private func generateFacePrint(for observation: VNFaceObservation, in cgImage: CGImage) -> Data? {
        let boundingBox = observation.boundingBox
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let rect = CGRect(
            x: boundingBox.origin.x * width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * height,
            width: boundingBox.width * width,
            height: boundingBox.height * height
        )
        
        guard let faceCrop = cgImage.cropping(to: rect) else {
            return nil
        }
        
        let featurePrintRequest = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: faceCrop, options: [:])
        
        do {
            try handler.perform([featurePrintRequest])
            guard let featurePrint = featurePrintRequest.results?.first as? VNFeaturePrintObservation else {
                return nil
            }
            
            return try NSKeyedArchiver.archivedData(withRootObject: featurePrint, requiringSecureCoding: true)
        } catch {
            return nil
        }
    }
    
    private func isFaceNew(facePrint: Data?) -> Bool {
        guard let newFacePrintData = facePrint,
              let newFaceprint = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: newFacePrintData) else {
            return true
        }
        
        for existingFacePrintData in recentlyShownFacePrints {
            guard let existingFaceprint = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: existingFacePrintData) else {
                continue
            }
            
            do {
                var distance = Float(0)
                try newFaceprint.computeDistance(&distance, to: existingFaceprint)
                
                if distance < similarityThreshold {
                    return false
                }
            } catch {
                continue
            }
        }
        
        return true
    }
    
    private func updateProgressLabel() {
        if totalFacesSaved == 0 {
            progressLabel.text = "Looking for different people in your photos..."
        } else {
            progressLabel.text = "🎉 \(totalFacesSaved) \(totalFacesSaved == 1 ? "face" : "faces") named so far"
        }
    }
    
    @objc private func skipPhotoTapped() {
        saveCurrentFaces()
        loadNextPhotoWithFaces()
    }
    
    @objc private func doneTapped() {
        finish()
    }
    
    private func saveCurrentFaces() {
        guard let photoData = currentPhotoData else { return }
        
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
            print("✅ Saved \(faceAssignments.filter { !$0.isEmpty }.count) faces from current photo")
        } catch {
            print("❌ Failed to save faces: \(error)")
        }
        
        totalPhotosProcessed += 1
    }
    
    private func showNoMorePhotosAlert() {
        let message: String
        if totalFacesSaved > 0 {
            message = "You've named \(totalFacesSaved) different \(totalFacesSaved == 1 ? "person" : "people") from your photos!"
        } else {
            message = "No more unique faces found. You can add faces anytime from the photo library."
        }
        
        let alert = UIAlertController(
            title: "All Done!",
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Finish", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.welcomeFaceNamingViewControllerDidFinish(self)
        })
        
        present(alert, animated: true)
    }
    
    private func finish() {
        saveCurrentFaces()
        
        let message: String
        if totalFacesSaved > 0 {
            message = "Great! You named \(totalFacesSaved) different \(totalFacesSaved == 1 ? "person" : "people"). You can add more anytime from the photo library."
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
            saveCurrentFaces()
            loadNextPhotoWithFaces()
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
            statusIndicator.isHidden = false
        } else {
            statusIndicator.isHidden = true
        }
    }
    
    override var isSelected: Bool {
        didSet {
            imageView.layer.borderColor = isSelected ? UIColor.systemBlue.cgColor : UIColor.clear.cgColor
            imageView.layer.borderWidth = isSelected ? 3 : 2
        }
    }
}