import UIKit
import SwiftUI
import SwiftData
import Photos
import Vision
import AVFoundation

protocol WelcomeFaceNamingViewControllerDelegate: AnyObject {
    func welcomeFaceNamingViewControllerDidFinish(_ controller: WelcomeFaceNamingViewController)
}

final class WelcomeFaceNamingViewController: UIViewController {
    
    weak var delegate: WelcomeFaceNamingViewControllerDelegate?
    
    private var prioritizedAssets: [PHAsset]
    /// Global index of prioritizedAssets[0] in the library (newest-first). 0 = at start; increases when we slide toward older.
    private var windowStartIndex: Int = 0
    private var isSlidingWindow = false
    /// Trigger slide when user is within this many items of the end or start of the window. Small = only when actually near the edge.
    private let slideTriggerMargin = 80
    /// Number of items to drop and fetch when sliding. Must be < initial window size (500) so we roll the window, not replace it.
    private let slideWindowChunk = 120
    private let modelContext: ModelContext
    private let imageManager = PHCachingImageManager()
    private let imageCache = ImageCacheService.shared

    private var currentPhotoData: (image: UIImage, date: Date, asset: PHAsset)?
    private var detectedFaces: [DetectedFaceInfo] = []
    private var faceAssignments: [String] = []
    /// When user picks a contact from autocomplete, we store it so we add the photo to that contact instead of creating a new one.
    private var faceAssignedExistingContact: [Int: Contact] = [:]
    private var totalFacesSaved = 0
    private var totalPhotosProcessed = 0
    private var isLoadingNextPhoto = false
    
    private var recentlyShownFacePrints: [Data] = []
    private let maxRecentFaces = 30
    private let similarityThreshold: Float = 0.5
    
    /// Size used for face detection and video frame extraction (kept moderate for performance).
    private let detectionTargetSize = CGSize(width: 1024, height: 1024)
    /// Larger size for the main photo display so the image looks sharp full-screen (Retina).
    private let mainDisplayTargetSize = CGSize(width: 2048, height: 2048)
    /// Smaller size for preprocessing-only (face count); faster load/decode than main display.
    private let preprocessingImageSize = CGSize(width: 512, height: 512)
    
    private var photoQueue: [PhotoCandidate] = []
    private var carouselThumbnails: [UIImage?] = []
    private var currentCarouselIndex = 0
    private var currentBatchIndex = 0
    
    // UserDefaults keys for persisting carousel position (index + asset ID for reliability when list changes)
    private let carouselPositionKey = "WelcomeFaceNaming.LastCarouselPosition"
    private let carouselPositionAssetIDKey = "WelcomeFaceNaming.LastCarouselPositionAssetID"
    /// UserDefaults key for asset IDs archived from carousel (to later delete for real).
    static let archivedAssetIDsKey = "WelcomeFaceNaming.ArchivedAssetIDs"
    /// Cached carousel asset IDs (filtered: screenshots with no faces removed). Used for instant open when gallery unchanged.
    static let cachedCarouselAssetIDsKey = "WelcomeFaceNaming.CachedCarouselAssetIDs"
    /// When true, cached carousel is stale (e.g. photo library changed or user archived). Rebuild on next open.
    static let cacheInvalidatedKey = "WelcomeFaceNaming.CacheInvalidated"
    /// Batch size for magnifying-glass preprocessing. Smaller = faster per batch, more batches. Images only (videos skipped).
    private let batchSize = 18
    /// Minimum seconds between photos when using Next (magnifying glass). Skips burst/duplicate group shots.
    private let nextPhotoMinimumTimeInterval: TimeInterval = 60
    private var isPreprocessing = false
    /// On phone we defer preprocessing until after the first photo is shown so resources aren't contended.
    private var shouldDeferPreprocessUntilFirstPhotoShown: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    private var didStartDeferredPreprocess = false
    private var thumbnailLoadingTasks: [Int: Task<Void, Never>] = [:]
    /// In-flight main image load; cancelled when user scrolls or taps to another index so stale result is not applied.
    private var mainImageLoadTask: Task<Void, Never>?
    private var isUserTappingCarousel = false
    private var hasUserStoppedScrolling = false
    private var isProgrammaticallyScrollingCarousel = false
    /// Only update/save carousel position from scroll delegate when user has dragged or tapped carousel (avoids overwriting restored position from programmatic scroll or layout).
    private var hasUserInteractedWithCarousel = false
    /// Set to true after applying restored carousel position so we never show index 0 before jumping to saved index.
    private var hasAppliedInitialCarouselPosition = false
    /// Selection ring is shown only when the carousel has stopped moving (not during scroll).
    private var carouselSelectionVisible = true
    // Apple Photos pattern: Pre-cached display images for instant scrolling
    private var cachedDisplayImages: [Int: UIImage] = [:]
    /// Cached display images for instant scrolling; sized for sharp display (was 512 on phone, too soft full-screen).
    private var displayImageSize: CGSize {
        UIDevice.current.userInterfaceIdiom == .phone
            ? CGSize(width: 1024, height: 1024)
            : CGSize(width: 1440, height: 1440)
    }
    /// Cache window each side for main display images. Phone uses smaller window to stay within memory limits.
    private var cacheWindowSize: Int {
        UIDevice.current.userInterfaceIdiom == .phone ? 8 : 20
    }
    /// Extra keys to keep outside the cache window (fast swipe-back). Smaller on phone to reduce memory.
    private var displayCacheBuffer: Int {
        UIDevice.current.userInterfaceIdiom == .phone ? 5 : 10
    }
    /// Last window passed to startCachingImages (display size); used to call stopCachingImages when the window moves.
    private var lastCachedDisplayWindow: (start: Int, end: Int)?
    
    /// Carousel strip: thumbnail size for the horizontal strip. Matches loadThumbnailImage so PH preheat hits request cache.
    private let carouselThumbnailSize = CGSize(width: 150, height: 150)
    /// PHCachingImageManager window each side for the carousel strip. Bounded so we don't cache thousands on large libraries.
    private var stripCacheWindowSize: Int {
        UIDevice.current.userInterfaceIdiom == .phone ? 20 : 30
    }
    /// Last window passed to startCachingImages (carousel thumbnail size); used to stopCaching when the window moves.
    private var lastCarouselThumbnailWindow: (start: Int, end: Int)?
    /// Center index at which we last ran cache window update (eviction). Used to throttle eviction during scroll.
    private var lastEvictionCenterIndex: Int?
    /// Minimum movement (in items) before we run eviction again during scroll. Keeps memory bounded during long fast scrolls.
    private let evictionScrollStride = 15
    /// Deferred scroll commitment: commit (save position, cache window, eviction) only when scroll has settled or ended. Large-app pattern to avoid thrashing PH/IO during fast scrolls.
    private var scrollCommitWorkItem: DispatchWorkItem?
    private let scrollSettleInterval: TimeInterval = 0.12

    // Video player properties
    private var videoPlayer: AVPlayer?
    private var videoPlayerLayer: AVPlayerLayer?
    private var currentVideoAsset: PHAsset?
    private var faceDetectionTimer: Timer?
    private var controlsHideTimer: Timer?
    private var lastDetectionTime: TimeInterval = 0
    private let detectionInterval: TimeInterval = 0.8  // Detect faces every 0.8 seconds for more responsiveness
    private var timeObserver: Any?
    
    // Layout constraints that change based on video vs image
    private var facesBottomConstraintForVideo: NSLayoutConstraint?
    private var facesBottomConstraintForImage: NSLayoutConstraint?
    
    // For video scrubbing gesture
    private var videoScrubStartTime: TimeInterval = 0
    private var isScrubbing = false
    
    private struct PhotoCandidate: Comparable {
        let asset: PHAsset
        let faceCount: Int
        let index: Int
        
        static func < (lhs: PhotoCandidate, rhs: PhotoCandidate) -> Bool {
            // Prioritize chronological order (index) to maintain strict chronological sorting
            // This ensures photos are shown from newest to oldest as fetched from the library
            return lhs.index < rhs.index
        }
    }
    
    private struct DetectedFaceInfo {
        /// Zoomed crop for the face chips overlay on the photo (tighter so face reads clearly).
        let displayImage: UIImage
        /// Wider crop for saving to contact photo (more space around face).
        let image: UIImage
        let boundingBox: CGRect
        let facePrint: Data?
    }
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Name Faces"
        label.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.textColor = .label
        label.numberOfLines = 1
        return label
    }()
    
    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Add names to people from your photos"
        label.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()
    
    // Container for photo/video content — clear so image/video appears to float on the screen background
    private lazy var photoContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        return view
    }()
    
    private lazy var photoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        return imageView
    }()
    
    private lazy var videoPlayerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear  // Match photo container; image/video floats on screen background
        view.isHidden = true
        view.isUserInteractionEnabled = true
        
        // Add tap gesture to play/pause video
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleVideoTap))
        view.addGestureRecognizer(tapGesture)
        
        // Add pan gesture to scrub video (Apple native pattern - drag to scrub)
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleVideoPanGesture(_:)))
        view.addGestureRecognizer(panGesture)
        
        // Allow both gestures to work together
        tapGesture.require(toFail: panGesture)
        
        return view
    }()
    
    // Video controls container with iOS-style dark translucent background
    private lazy var videoControlsContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true
        container.alpha = 0  // Start hidden for smooth fade-in
        
        // Add dark translucent background like iOS video player
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 8
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        
        container.insertSubview(blurView, at: 0)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: container.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        
        return container
    }()
    
    private lazy var playPauseButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        button.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
        button.addTarget(self, action: #selector(playPauseButtonTapped), for: .touchUpInside)
        
        return button
    }()
    
    private lazy var videoProgressSlider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = 0
        
        // iOS-style video player colors
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        slider.thumbTintColor = .white
        
        // Make the thumb smaller and more subtle
        let thumbImage = createCircleThumb(radius: 6, color: .white)
        slider.setThumbImage(thumbImage, for: .normal)
        slider.setThumbImage(thumbImage, for: .highlighted)
        
        slider.addTarget(self, action: #selector(videoSliderChanged(_:)), for: .valueChanged)
        slider.addTarget(self, action: #selector(videoSliderTouchBegan(_:)), for: .touchDown)
        slider.addTarget(self, action: #selector(videoSliderTouchEnded(_:)), for: [.touchUpInside, .touchUpOutside])
        
        return slider
    }()
    
    private var isSeekingVideo = false
    
    // Helper function to create circular thumb for slider
    private func createCircleThumb(radius: CGFloat, color: UIColor) -> UIImage? {
        let size = CGSize(width: radius * 2, height: radius * 2)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            let circle = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
            circle.fill()
        }
    }
    
    private lazy var facesCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        // Align with video controls: 8pt container leading + 32pt button + 8pt spacing = 48pt
        layout.sectionInset = UIEdgeInsets(top: 8, left: 48, bottom: 8, right: 8)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.allowsSelection = true
        collectionView.register(FaceCell.self, forCellWithReuseIdentifier: FaceCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        
        return collectionView
    }()
    
    private lazy var nameTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Type a name"
        textField.font = UIFont.systemFont(ofSize: 17)
        textField.borderStyle = .none
        textField.autocapitalizationType = .words
        textField.autocorrectionType = .no
        textField.returnKeyType = .done
        textField.delegate = self
        textField.addTarget(self, action: #selector(nameTextFieldEditingChanged), for: .editingChanged)
        
        // Match QuickInputView InputBubble: 56pt height, pill shape (cornerRadius = height/2), 16pt horizontal padding
        let inputRowHeight: CGFloat = 56
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = inputRowHeight / 2
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        blurView.isUserInteractionEnabled = false
        
        textField.insertSubview(blurView, at: 0)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: textField.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: textField.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: textField.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: textField.bottomAnchor),
        ])
        
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: inputRowHeight))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: inputRowHeight))
        textField.rightViewMode = .always
        
        return textField
    }()
    
    // Contact autocompletion (same logic as QuickInputView / NameAutocompleteField)
    private var allContacts: [Contact] = []
    private var suggestedContacts: [Contact] = []
    private static let nameSuggestionsMaxCount = 5
    private static let nameSuggestionsRowHeight: CGFloat = 44
    private static let nameSuggestionsMaxHeight: CGFloat = 200
    
    private lazy var nameSuggestionsTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(NameSuggestionCell.self, forCellReuseIdentifier: NameSuggestionCell.reuseId)
        table.rowHeight = Self.nameSuggestionsRowHeight
        table.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 0)
        table.backgroundColor = .secondarySystemGroupedBackground
        table.layer.cornerRadius = 10
        table.layer.cornerCurve = .continuous
        table.clipsToBounds = true
        table.isScrollEnabled = true
        table.bounces = false
        table.isHidden = true
        return table
    }()
    
    private var nameSuggestionsTableHeightConstraint: NSLayoutConstraint?
    private var nameTextFieldHeightConstraint: NSLayoutConstraint?
    /// Buttons below carousel when no faces; inactive when name section is visible.
    private var carouselToButtonsConstraint: NSLayoutConstraint?
    /// Buttons below name suggestions when faces detected; inactive when name section hidden.
    private var nameSectionToButtonsConstraint: NSLayoutConstraint?
    /// Carousel bottom pinned above buttons (so photo fills); inactive when name section visible.
    private var carouselBottomToButtonsTopConstraint: NSLayoutConstraint?
    
    /// Container for the liquid glass "Next" (magnifying glass) button. Retained for layout and keyboard alpha.
    private lazy var nextButtonContainerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    /// Liquid glass magnifying glass button (Next). Retained via addChild when set in setupView.
    private var nextButtonHostingController: UIHostingController<LiquidGlassNextButtonView>?

    /// Spacer row below carousel/name section (keeps layout; magnifying glass is at carousel height on the left).
    private lazy var carouselButtonsStackView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [spacer])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.distribution = .fill
        return stack
    }()
    
    private lazy var photoCarouselCollectionView: UICollectionView = {
        let layout = PhotoCarouselFlowLayout()
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = UIColor.systemBackground
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast  // Faster, more responsive scrolling
        collectionView.alwaysBounceHorizontal = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.clipsToBounds = true
        collectionView.register(PhotoCarouselCell.self, forCellWithReuseIdentifier: PhotoCarouselCell.reuseIdentifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.isPrefetchingEnabled = true
        return collectionView
    }()
    
    // Fade effect masks for carousel edges (systemGroupedBackground with 0-opacity equivalent instead of clear)
    private lazy var carouselLeftFadeView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        
        let gradientLayer = CAGradientLayer()
        let groupedBg = UIColor.systemGroupedBackground
        gradientLayer.colors = [
            groupedBg.cgColor,
            groupedBg.withAlphaComponent(0).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations = [0, 1]
        view.layer.addSublayer(gradientLayer)
        
        return view
    }()
    
    /// Transparent overlay on the leading edge of the carousel; tap = jump to first photo. No overlap with cell touch targets.
    private lazy var carouselLeadingTapOverlay: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCarouselEmptyAreaTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }()
    
    private lazy var carouselRightFadeView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        
        let gradientLayer = CAGradientLayer()
        let groupedBg = UIColor.systemGroupedBackground
        gradientLayer.colors = [
            groupedBg.withAlphaComponent(0).cgColor,
            groupedBg.cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations = [0, 1]
        view.layer.addSublayer(gradientLayer)
        
        return view
    }()
    
    
    private var currentFaceIndex = 0

    /// Close button with liquid glass circle (same look as ContactDetailsView). Retained via addChild.
    private var closeButtonHostingController: UIHostingController<LiquidGlassCloseButton>?

    /// When non-nil (e.g. when opened from a group header), the carousel scrolls to the photo at or nearest this date.
    private let initialScrollDate: Date?

    /// When true (tab context), QuickInput replaces the built-in name field; hide nameTextField and sync via notifications.
    private let useQuickInputForName: Bool

    /// When set (e.g. by SwiftUI host), called after the VC mutates prioritizedAssets (e.g. archive) so the host can sync its state and not overwrite the list on next update.
    var onPrioritizedAssetsDidChange: (([PHAsset]) -> Void)?

    init(prioritizedAssets: [PHAsset], modelContext: ModelContext, initialScrollDate: Date? = nil, useQuickInputForName: Bool = false) {
        self.prioritizedAssets = prioritizedAssets
        self.modelContext = modelContext
        self.initialScrollDate = initialScrollDate
        self.useQuickInputForName = useQuickInputForName
        super.init(nibName: nil, bundle: nil)
        
        imageManager.allowsCachingHighQualityImages = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: .photoLibraryDidBecomeUnavailable, object: nil)
        NotificationCenter.default.removeObserver(self, name: .quickInputTextDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .quickInputFaceNameSubmit, object: nil)
        imageManager.stopCachingImagesForAllAssets()
        cleanupVideoPlayer()
        cachedDisplayImages.removeAll()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Restore saved carousel position
        restoreCarouselPosition()
        
        setupView()
        fetchContacts()
        setupCarousel()
        setupKeyboardHandling()
        setupKeyboardDismissGestures()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarningNotification),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePhotoLibraryUnavailable),
            name: .photoLibraryDidBecomeUnavailable,
            object: nil
        )
        if useQuickInputForName {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleQuickInputTextDidChange(_:)),
                name: .quickInputTextDidChange,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleQuickInputFaceNameSubmit),
                name: .quickInputFaceNameSubmit,
                object: nil
            )
        }
        // On phone, defer preprocessing until first photo is shown. On iPad, defer briefly so initial paint is smooth.
        if !shouldDeferPreprocessUntilFirstPhotoShown {
            deferPreprocessNextBatch()
        }
    }
    
    private static let contactsFetchLimitForSuggestions = 500

    private func fetchContacts() {
        do {
            let predicate = #Predicate<Contact> { contact in
                contact.isArchived == false
            }
            var descriptor = FetchDescriptor<Contact>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.name)]
            )
            descriptor.fetchLimit = Self.contactsFetchLimitForSuggestions
            allContacts = try modelContext.fetch(descriptor)
        } catch {
            print("WelcomeFaceNaming: failed to fetch contacts for suggestions: \(error)")
        }
    }
    
    private func filterContactsForNameSuggestions() {
        let query = (nameTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            suggestedContacts = []
        } else {
            suggestedContacts = allContacts.filter { contact in
                guard let name = contact.name, !query.isEmpty else { return false }
                return name.localizedStandardContains(query) || name.lowercased().hasPrefix(query.lowercased())
            }
            suggestedContacts = Array(suggestedContacts.prefix(Self.nameSuggestionsMaxCount))
        }
        nameSuggestionsTableView.reloadData()
        let showTable = !suggestedContacts.isEmpty && nameTextField.isFirstResponder
        nameSuggestionsTableView.isHidden = !showTable
        let height: CGFloat = showTable
            ? min(Self.nameSuggestionsMaxHeight, CGFloat(suggestedContacts.count) * Self.nameSuggestionsRowHeight)
            : 0
        nameSuggestionsTableHeightConstraint?.constant = height
    }
    
    @objc private func handleQuickInputTextDidChange(_ notification: Notification) {
        guard useQuickInputForName,
              let text = notification.userInfo?["text"] as? String,
              currentFaceIndex < faceAssignments.count else { return }
        faceAssignedExistingContact.removeValue(forKey: currentFaceIndex)
        faceAssignments[currentFaceIndex] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let indexPath = IndexPath(item: currentFaceIndex, section: 0)
        facesCollectionView.reloadItems(at: [indexPath])
    }

    @objc private func handleQuickInputFaceNameSubmit() {
        guard useQuickInputForName, !detectedFaces.isEmpty else { return }
        let name = (currentFaceIndex < faceAssignments.count) ? faceAssignments[currentFaceIndex].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if currentFaceIndex < faceAssignments.count {
            faceAssignments[currentFaceIndex] = name
        }
        let indexPath = IndexPath(item: currentFaceIndex, section: 0)
        facesCollectionView.reloadItems(at: [indexPath])
        if !name.isEmpty && currentFaceIndex < detectedFaces.count - 1 {
            currentFaceIndex += 1
            let nextIndexPath = IndexPath(item: currentFaceIndex, section: 0)
            facesCollectionView.selectItem(at: nextIndexPath, animated: true, scrollPosition: .centeredHorizontally)
            syncQuickInputWithCurrentFace()
            NotificationCenter.default.post(name: .quickInputRequestFocus, object: nil)
        }
    }

    private func syncQuickInputWithCurrentFace() {
        guard useQuickInputForName else { return }
        let name = (currentFaceIndex < faceAssignments.count) ? faceAssignments[currentFaceIndex] : ""
        NotificationCenter.default.post(name: .quickInputSetFaceName, object: nil, userInfo: ["text": name])
    }

    @objc private func nameTextFieldEditingChanged() {
        guard !useQuickInputForName else { return }
        // User typed; if they had picked an existing contact, treat this as a new name (don't add photo to that contact).
        faceAssignedExistingContact.removeValue(forKey: currentFaceIndex)
        filterContactsForNameSuggestions()
    }
    
    private func setupCarousel() {
        // Initialize carousel with all available photos (unfiltered); count is single source of truth.
        carouselThumbnails = Array(repeating: nil, count: carouselItemCount)
        photoCarouselCollectionView.reloadData()
        
        // Preload thumbnails around restored position
        loadInitialCarouselThumbnails()
        
        // Apple Photos pattern: Pre-cache display images immediately for instant scrolling
        startCachingDisplayImages(around: currentCarouselIndex)
    }
    
    @objc private func handleMemoryWarningNotification() {
        // #region agent log
        debugSessionLog(location: "WelcomeFaceNamingVC:handleMemoryWarningNotification", message: "VC memory warning handler", data: ["cachedCount": cachedDisplayImages.count, "thumbSlots": carouselThumbnails.count], hypothesisId: "H3")
        // #endregion
        mainImageLoadTask?.cancel()
        mainImageLoadTask = nil
        cleanupVideoPlayer()
        cachedDisplayImages.removeAll()
        lastCachedDisplayWindow = nil
        lastCarouselThumbnailWindow = nil
        lastEvictionCenterIndex = nil
        imageManager.stopCachingImagesForAllAssets()
        // Keep only thumbnails very close to current position; cancel in-flight loads outside that window
        let margin = 15
        let low = max(0, currentCarouselIndex - margin)
        let high = carouselItemCount > 0 ? min(carouselItemCount - 1, currentCarouselIndex + margin) : -1
        for i in 0..<carouselItemCount where i < low || i > high {
            thumbnailLoadingTasks[i]?.cancel()
            thumbnailLoadingTasks.removeValue(forKey: i)
            carouselThumbnails[i] = nil
        }
    }

    @objc private func handlePhotoLibraryUnavailable() {
        cleanupVideoPlayer()
        imageManager.stopCachingImagesForAllAssets()
        cachedDisplayImages.removeAll()
        lastCachedDisplayWindow = nil
        lastCarouselThumbnailWindow = nil
        let alert = UIAlertController(
            title: "Photos Unavailable",
            message: "The photo library was disconnected, often due to low memory. You can try again from the photo library later.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.clearSavedPosition()
            self.delegate?.welcomeFaceNamingViewControllerDidFinish(self)
        })
        present(alert, animated: true)
    }
    
    @objc private func handleCarouselEmptyAreaTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, carouselItemCount > 0 else { return }
        hasUserInteractedWithCarousel = true
        isUserTappingCarousel = true
        jumpToPhotoAtIndex(0)
    }
    
    /// Called when SwiftUI passes a new asset list (e.g. after background merge of screenshots-with-faces). Only updates if the list actually changed.
    func updatePrioritizedAssetsIfNeeded(_ newAssets: [PHAsset]) {
        guard newAssets.count != prioritizedAssets.count ||
              !zip(prioritizedAssets, newAssets).allSatisfy({ $0.localIdentifier == $1.localIdentifier }) else { return }
        // #region agent log
        debugSessionLog(location: "WelcomeFaceNamingVC:updatePrioritizedAssetsIfNeeded", message: "Replacing asset list", data: ["oldCount": prioritizedAssets.count, "newCount": newAssets.count], hypothesisId: "H2")
        // #endregion
        // When list changes, try to keep showing the same photo by asset ID (more reliable than index)
        let savedAssetID = UserDefaults.standard.string(forKey: carouselPositionAssetIDKey)
        prioritizedAssets = newAssets
        carouselThumbnails = Array(repeating: nil, count: carouselItemCount)
        if let id = savedAssetID, let index = newAssets.firstIndex(where: { $0.localIdentifier == id }) {
            currentCarouselIndex = index
        } else {
            currentCarouselIndex = clampCarouselIndex(currentCarouselIndex)
        }
        cachedDisplayImages.removeAll()
        lastCachedDisplayWindow = nil
        lastCarouselThumbnailWindow = nil
        photoCarouselCollectionView.reloadData()
        scrollCarouselToCurrentIndex()
        loadPhotoAtCarouselIndex(currentCarouselIndex)
        startCachingDisplayImages(around: currentCarouselIndex)
        loadVisibleAndNearbyThumbnails()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("[NF] Name Faces appeared, process memory: \(ProcessMemoryReporter.currentMegabytesString)")
        
        ProcessReportCoordinator.shared.register(name: "WelcomeFaceNamingViewController") { [weak self] in
            guard let self else {
                return ProcessReportSnapshot(name: "WelcomeFaceNamingViewController", payload: ["state": "released"])
            }
            let nonNilThumbs = self.carouselThumbnails.lazy.filter { $0 != nil }.count
            return ProcessReportSnapshot(
                name: "WelcomeFaceNamingViewController",
                payload: [
                    "cachedDisplayCount": "\(self.cachedDisplayImages.count)",
                    "carouselThumbSlots": "\(self.carouselThumbnails.count)",
                    "carouselThumbsLoaded": "\(nonNilThumbs)",
                    "prioritizedAssetsCount": "\(self.prioritizedAssets.count)"
                ]
            )
        }
        
        // Fallback: apply restored position if not yet applied (e.g. carousel was empty at first layout)
        if !hasAppliedInitialCarouselPosition, carouselItemCount > 0 {
            print("[NF] viewDidAppear: fallback applying saved position index=\(currentCarouselIndex)")
            hasAppliedInitialCarouselPosition = true
            scrollToSavedPosition()
        }
        // Refinement for initialScrollDate can run after appear
        if initialScrollDate != nil {
            DispatchQueue.main.async { [weak self] in
                self?.refineToBestPhotoOnInitialDateIfNeeded()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("[NF] Name Faces will disappear, process memory: \(ProcessMemoryReporter.currentMegabytesString)")
        ProcessReportCoordinator.shared.unregister(name: "WelcomeFaceNamingViewController")
        // So next appearance re-applies saved position (handles SwiftUI re-presenting same VC)
        hasAppliedInitialCarouselPosition = false
    }
    
    // MARK: - Position Persistence
    
    private func restoreCarouselPosition() {
        if let targetDate = initialScrollDate {
            currentCarouselIndex = indexForDate(targetDate)
            currentCarouselIndex = clampCarouselIndex(currentCarouselIndex)
            print("📍 Opening at group date: index \(currentCarouselIndex) for date \(targetDate)")
            return
        }
        guard carouselItemCount > 0 else {
            currentCarouselIndex = 0
            return
        }
        let savedIndex = UserDefaults.standard.integer(forKey: carouselPositionKey)
        let savedAssetID = UserDefaults.standard.string(forKey: carouselPositionAssetIDKey)
        // Prefer restoring by asset ID so we show the same photo when list order/count changes (e.g. cache refresh)
        if let id = savedAssetID, let index = prioritizedAssets.firstIndex(where: { $0.localIdentifier == id }) {
            currentCarouselIndex = index
            print("📍 Restored carousel position to index \(index) by asset ID")
        } else {
            // Fall back to saved index, clamped to valid range (avoid jumping to 0 when list shrinks)
            currentCarouselIndex = clampCarouselIndex(savedIndex)
            print("📍 Restored carousel position to index \(currentCarouselIndex) (clamped from \(savedIndex))")
        }
    }
    
    /// Single source of truth for how many items are in the carousel. Always equals prioritizedAssets.count.
    private var carouselItemCount: Int { prioritizedAssets.count }

    /// True iff index is in [0, carouselItemCount - 1]. Use for any carousel index before accessing prioritizedAssets or carouselThumbnails.
    private func isValidCarouselIndex(_ index: Int) -> Bool {
        (0..<carouselItemCount).contains(index)
    }

    /// Clamp index to [0, carouselItemCount - 1]. Returns 0 if list is empty.
    private func clampCarouselIndex(_ index: Int) -> Int {
        guard carouselItemCount > 0 else { return 0 }
        return min(max(0, index), carouselItemCount - 1)
    }

    /// Index in prioritizedAssets (newest-first) whose creation date is on the same day as `date`, or closest to it.
    private func indexForDate(_ date: Date) -> Int {
        let indices = indicesOnSameDay(as: date)
        if let first = indices.first {
            return first
        }
        var bestIndex = 0
        var bestInterval: TimeInterval = .infinity
        for (index, asset) in prioritizedAssets.enumerated() {
            let creation = asset.creationDate ?? Date()
            let interval = abs(creation.timeIntervalSince(date))
            if interval < bestInterval {
                bestInterval = interval
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// All indices in prioritizedAssets (newest-first) whose creation date is on the same calendar day as `date`.
    private func indicesOnSameDay(as date: Date) -> [Int] {
        let calendar = Calendar.current
        let targetStart = calendar.startOfDay(for: date)
        return prioritizedAssets.enumerated()
            .filter { _, asset in
                guard let creation = asset.creationDate else { return false }
                return calendar.isDate(creation, inSameDayAs: targetStart)
            }
            .map(\.offset)
    }

    /// When opened with initialScrollDate, find the photo on that day with the most faces (same relevance as photo queue) and scroll to it.
    private func refineToBestPhotoOnInitialDateIfNeeded() {
        guard let date = initialScrollDate else { return }
        let dayIndices = indicesOnSameDay(as: date)
        guard dayIndices.count > 1 else { return }

        Task {
            var results: [(index: Int, faceCount: Int)] = []
            for index in dayIndices {
                guard isValidCarouselIndex(index) else { continue }
                let asset = prioritizedAssets[index]
                guard asset.mediaType == .image else { continue }
                guard let image = await loadOptimizedImage(for: asset) else { continue }
                let count = await countFaces(in: image)
                results.append((index: index, faceCount: count))
            }
            guard !results.isEmpty else { return }
            // Same relevance as preprocess: prefer 2+ faces, then by most faces, then newest (smaller index)
            let best = results
                .sorted { a, b in
                    let aRelevant = a.faceCount >= 2
                    let bRelevant = b.faceCount >= 2
                    if aRelevant != bRelevant { return aRelevant }
                    if a.faceCount != b.faceCount { return a.faceCount > b.faceCount }
                    return a.index < b.index
                }
                .first!
            await MainActor.run {
                guard best.index != self.currentCarouselIndex else { return }
                self.currentCarouselIndex = best.index
                self.isProgrammaticallyScrollingCarousel = true
                self.carouselSelectionVisible = false
                self.photoCarouselCollectionView.reloadItems(at: self.photoCarouselCollectionView.indexPathsForVisibleItems)
                let indexPath = IndexPath(item: best.index, section: 0)
                self.photoCarouselCollectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
                self.loadPhotoAtCarouselIndex(best.index)
                self.startCachingDisplayImages(around: best.index)
                print("📍 Refined to best photo on day: index \(best.index) with \(best.faceCount) faces")
            }
        }
    }

    /// Scrolls the carousel so the item at currentCarouselIndex is centered. Single path: use the collection view’s API so the layout owns the math. Do not reload after — that can invalidate layout and undo the scroll.
    private func scrollCarouselToCurrentIndex() {
        guard carouselItemCount > 0 else { return }
        currentCarouselIndex = clampCarouselIndex(currentCarouselIndex)
        view.layoutIfNeeded()
        photoCarouselCollectionView.layoutIfNeeded()
        let cv = photoCarouselCollectionView
        let indexPath = IndexPath(item: currentCarouselIndex, section: 0)
        cv.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
        carouselSelectionVisible = true
        // Do not reloadData/reloadItems here — our index is the source of truth; cells will get correct isCurrentPhoto when configured. Reloading can invalidate layout and desync the scroll we just did.
    }

    private func scrollToSavedPosition() {
        currentCarouselIndex = clampCarouselIndex(currentCarouselIndex)
        guard carouselItemCount > 0 else { return }
        
        // Prevent scroll delegate from overwriting restored index until the user actually drags
        hasUserInteractedWithCarousel = false
        isProgrammaticallyScrollingCarousel = true
        carouselSelectionVisible = false
        
        scrollCarouselToCurrentIndex()
        
        // Show main content for the restored index so photo and carousel match
        let idx = currentCarouselIndex
        if isValidCarouselIndex(idx) {
            let asset = prioritizedAssets[idx]
            let date = asset.creationDate ?? Date()
            if let cachedImage = cachedDisplayImages[idx] {
                applyMainImage(cachedImage, date: date, asset: asset, forCarouselIndex: idx)
            } else if asset.mediaType == .video, let thumb = carouselThumbnails[idx] {
                applyMainImage(thumb, date: date, asset: asset, forCarouselIndex: idx)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.loadPhotoAtCarouselIndex(self.currentCarouselIndex)
        }
        // Do not set isProgrammaticallyScrollingCarousel = false here; let scrollViewWillBeginDragging
        // set it when the user actually drags, so findCenteredItemIndex() never overwrites the restored index.
    }
    
    private func saveCarouselPosition() {
        let indexToSave = currentCarouselIndex
        let assetIDToSave: String? = isValidCarouselIndex(indexToSave)
            ? prioritizedAssets[indexToSave].localIdentifier
            : nil
        DispatchQueue.global(qos: .utility).async {
            UserDefaults.standard.set(indexToSave, forKey: self.carouselPositionKey)
            if let id = assetIDToSave {
                UserDefaults.standard.set(id, forKey: self.carouselPositionAssetIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: self.carouselPositionAssetIDKey)
            }
        }
    }
    
    private func clearSavedPosition() {
        UserDefaults.standard.removeObject(forKey: carouselPositionKey)
        UserDefaults.standard.removeObject(forKey: carouselPositionAssetIDKey)
        print("🗑️ Cleared saved carousel position")
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Apply restored carousel position before first paint so we never show index 0 then jump
        if !hasAppliedInitialCarouselPosition, carouselItemCount > 0, photoCarouselCollectionView.bounds.width > 0 {
            let savedAssetID = UserDefaults.standard.string(forKey: carouselPositionAssetIDKey)
            let assetAlreadyInList = savedAssetID.map { id in prioritizedAssets.contains { $0.localIdentifier == id } } ?? false
            if let id = savedAssetID, !assetAlreadyInList {
                // Saved photo is beyond initial 500 (e.g. user had used Next and left at index 685). Fetch until it's in the list.
                hasAppliedInitialCarouselPosition = true
                Task { [weak self] in
                    guard let self else { return }
                    let found = await self.fetchUntilSavedAssetPresent(assetID: id)
                    await MainActor.run {
                        if found {
                            self.restoreCarouselPosition()
                            self.scrollToSavedPosition()
                            self.onPrioritizedAssetsDidChange?(self.prioritizedAssets)
                        } else {
                            self.scrollToSavedPosition()
                        }
                    }
                }
            } else {
                print("[NF] viewDidLayoutSubviews: applying initial position index=\(currentCarouselIndex) bounds.width=\(photoCarouselCollectionView.bounds.width)")
                hasAppliedInitialCarouselPosition = true
                scrollToSavedPosition()
            }
        }
        
        // Update gradient layer frames and colors for carousel fade views (systemGroupedBackground; 0-opacity equivalent instead of clear)
        let groupedBg = UIColor.systemGroupedBackground
        let groupedBgClear = groupedBg.withAlphaComponent(0)
        if let gradientLayer = carouselLeftFadeView.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = carouselLeftFadeView.bounds
            gradientLayer.colors = [groupedBg.cgColor, groupedBgClear.cgColor]
        }
        
        if let gradientLayer = carouselRightFadeView.layer.sublayers?.first as? CAGradientLayer {
            gradientLayer.frame = carouselRightFadeView.bounds
            gradientLayer.colors = [groupedBgClear.cgColor, groupedBg.cgColor]
        }
        
        // Update video player layer: fit (resizeAspect), frame to bounds
        if let layer = videoPlayerLayer {
            layer.videoGravity = AVLayerVideoGravity.resizeAspect
            layer.frame = CGRect(origin: .zero, size: videoPlayerView.bounds.size)
        }
    }
    
    // MARK: - Layout Management
    
    private func configureLayoutForVideo() {
        // For video: faces start at bottom (will move up when user scrubs and shows controls)
        // DON'T automatically position above controls - let the scrubbing gesture handle that
        UIView.performWithoutAnimation {
            facesBottomConstraintForVideo?.isActive = false
            facesBottomConstraintForImage?.isActive = true  // Start at bottom
            view.layoutIfNeeded()
        }
    }
    
    private func configureLayoutForImage() {
        // Switch to image layout: faces at bottom
        // Disable implicit animations from Auto Layout
        UIView.performWithoutAnimation {
            facesBottomConstraintForVideo?.isActive = false
            facesBottomConstraintForImage?.isActive = true
            view.layoutIfNeeded()
        }
    }
    
    /// Single place that applies the main photo image and related state. Only applies if `currentCarouselIndex == index` to avoid stale async results.
    private func applyMainImage(_ image: UIImage, date: Date, asset: PHAsset, forCarouselIndex index: Int) {
        guard currentCarouselIndex == index else { return }
        currentPhotoData = (image: image, date: date, asset: asset)
        setMainImageContentMode(for: asset)
        photoImageView.image = image
        photoImageView.isHidden = false
        cleanupVideoPlayer()
        configureLayoutForImage()
    }
    
    private func updateFacesVisibility() {
        let hasFaces = !detectedFaces.isEmpty
        facesCollectionView.isHidden = !hasFaces

        if useQuickInputForName {
            nameTextField.isHidden = true
            nameSuggestionsTableView.isHidden = true
            carouselToButtonsConstraint?.isActive = true
            nameSectionToButtonsConstraint?.isActive = false
            carouselBottomToButtonsTopConstraint?.isActive = false
            syncQuickInputWithCurrentFace()
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.view.layoutIfNeeded()
            }
            return
        }

        // Name section is always visible (same placement/size as QuickInput); only faces strip toggles.
        let inputRowHeight: CGFloat = 56
        nameTextFieldHeightConstraint?.constant = inputRowHeight
        carouselToButtonsConstraint?.isActive = false
        nameSectionToButtonsConstraint?.isActive = false
        carouselBottomToButtonsTopConstraint?.isActive = false
        nameSectionToButtonsConstraint?.isActive = true
        carouselBottomToButtonsTopConstraint?.isActive = false

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.nameSuggestionsTableView.isHidden = self.suggestedContacts.isEmpty || !self.nameTextField.isFirstResponder
            self.view.layoutIfNeeded()
        }
    }
    
    // MARK: - Keyboard Handling
    
    private func setupKeyboardHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    private func setupKeyboardDismissGestures() {
        // Add tap gesture to dismiss keyboard when tapping outside
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
        
        // Add swipe down gesture to dismiss keyboard (native iOS behavior)
        let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        swipeGesture.direction = .down
        view.addGestureRecognizer(swipeGesture)
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        // Hide bottom controls when keyboard appears; use beginFromCurrentState to avoid layout thrash
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.nextButtonContainerView.alpha = 0
            self.photoCarouselCollectionView.alpha = 0
        }
    }
    
    @objc private func keyboardWillHide(_ notification: Notification) {
        // Show bottom controls when keyboard hides
        UIView.animate(withDuration: 0.3) {
            self.nextButtonContainerView.alpha = 1
            self.photoCarouselCollectionView.alpha = 1
        }
    }
    
    @objc private func closeTapped() {
        view.endEditing(true)
        
        // Save faces asynchronously to avoid blocking the exit animation
        Task.detached { [weak self] in
            await self?.saveCurrentFacesAsync()
        }
        
        // Clean up immediately (fast operation)
        cleanupVideoPlayer()
        
        // Dismiss immediately - don't wait for save to complete
        delegate?.welcomeFaceNamingViewControllerDidFinish(self)
    }
    
    @objc private func handleVideoTap() {
        guard let player = videoPlayer else { return }
        
        print("👆 Video tapped - toggling play/pause")
        
        // Toggle play/pause
        if player.timeControlStatus == .playing {
            player.pause()
            updatePlayPauseButton(isPlaying: false)
            print("⏸️ Video paused")
        } else {
            player.play()
            updatePlayPauseButton(isPlaying: true)
            print("▶️ Video playing")
        }
    }
    
    @objc private func handleVideoPanGesture(_ gesture: UIPanGestureRecognizer) {
        guard let player = videoPlayer,
              let duration = player.currentItem?.duration.seconds,
              duration.isFinite, duration > 0 else {
            return
        }
        
        switch gesture.state {
        case .began:
            // Start scrubbing - show controls and adjust faces layout
            print("📹 Pan gesture began - showing controls and moving faces up")
            isScrubbing = true
            isSeekingVideo = true
            videoScrubStartTime = player.currentTime().seconds
            cancelControlsAutoHide()
            
            // Show controls with faces moving up (Apple pattern)
            showVideoControlsWithFacesAdjustment()
            
        case .changed:
            // Calculate new time based on horizontal pan
            let translation = gesture.translation(in: videoPlayerView)
            let viewWidth = videoPlayerView.bounds.width
            
            // Map horizontal movement to video duration
            // Every 100 points = 1 second of video (adjust sensitivity here)
            let timeChange = Double(translation.x) / 100.0
            let newTime = max(0, min(duration, videoScrubStartTime + timeChange))
            
            // Update slider to reflect scrub position
            videoProgressSlider.value = Float(newTime / duration)
            
            // Seek to new time
            let targetTime = CMTime(seconds: newTime, preferredTimescale: 600)
            player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            
        case .ended, .cancelled, .failed:
            // End scrubbing - hide controls after delay and reset faces layout
            print("📹 Pan gesture ended - hiding controls after delay, moving faces down")
            isScrubbing = false
            isSeekingVideo = false
            
            // Hide controls after 1 second, faces will move back down
            scheduleControlsAutoHide(delay: 1.0)
            
        default:
            break
        }
    }
    
    @objc private func playPauseButtonTapped() {
        guard let player = videoPlayer else { return }
        
        // Toggle play/pause
        if player.timeControlStatus == .playing {
            player.pause()
            updatePlayPauseButton(isPlaying: false)
        } else {
            player.play()
            updatePlayPauseButton(isPlaying: true)
        }
        
        // Keep controls visible and restart auto-hide timer
        cancelControlsAutoHide()
        scheduleControlsAutoHide()
    }
    
    private func showVideoControlsWithFacesAdjustment() {
        guard videoControlsContainer.isHidden else { return }
        
        print("📊 Showing video controls + moving faces up")
        
        // Show controls and move faces up in one smooth animation
        videoControlsContainer.isHidden = false
        
        UIView.animate(withDuration: 0.25) {
            self.videoControlsContainer.alpha = 1
            
            // Switch faces constraint to position above controls
            self.facesBottomConstraintForImage?.isActive = false
            self.facesBottomConstraintForVideo?.isActive = true
            self.view.layoutIfNeeded()
        }
    }
    
    private func scheduleControlsAutoHide(delay: TimeInterval = 3.0) {
        cancelControlsAutoHide()
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.hideVideoControlsWithFacesAdjustment()
        }
    }
    
    private func cancelControlsAutoHide() {
        controlsHideTimer?.invalidate()
        controlsHideTimer = nil
    }
    
    private func hideVideoControlsWithFacesAdjustment() {
        guard !videoControlsContainer.isHidden else { return }
        
        print("📊 Hiding video controls + moving faces down")
        
        // Hide controls and move faces down in one smooth animation
        UIView.animate(withDuration: 0.25) {
            self.videoControlsContainer.alpha = 0
            
            // Switch faces constraint to position at bottom
            self.facesBottomConstraintForVideo?.isActive = false
            self.facesBottomConstraintForImage?.isActive = true
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.videoControlsContainer.isHidden = true
        }
    }
    
    private func updatePlayPauseButton(isPlaying: Bool) {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        let imageName = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.setImage(UIImage(systemName: imageName, withConfiguration: config), for: .normal)
    }
    
    @objc private func videoSliderChanged(_ slider: UISlider) {
        guard let player = videoPlayer,
              let duration = player.currentItem?.duration.seconds,
              duration.isFinite else {
            return
        }
        
        let targetTime = CMTime(seconds: Double(slider.value) * duration, preferredTimescale: 600)
        player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    @objc private func videoSliderTouchBegan(_ slider: UISlider) {
        isSeekingVideo = true
        // Cancel auto-hide while user is scrubbing via slider
        cancelControlsAutoHide()
    }
    
    @objc private func videoSliderTouchEnded(_ slider: UISlider) {
        isSeekingVideo = false
        // Resume auto-hide after scrubbing via slider
        scheduleControlsAutoHide(delay: 1.0)
    }
    
    @objc private func periodicFaceDetection() {
        guard let player = videoPlayer,
              let asset = currentVideoAsset,
              asset.mediaType == .video else {
            return
        }
        
        let currentTime = player.currentTime().seconds
        
        // Skip detection if paused or if not enough time has passed
        if player.timeControlStatus != .playing {
            return
        }
        
        guard currentTime - lastDetectionTime >= detectionInterval else {
            return
        }
        
        lastDetectionTime = currentTime
        
        print("📹 Auto-detecting faces at \(String(format: "%.1f", currentTime))s")
        
        Task {
            guard let currentImage = await captureCurrentVideoFrame() else {
                return
            }
            
            // Store current face count before detection
            let previousFaceCount = await MainActor.run { self.detectedFaces.count }
            
            // Run face detection on current frame
            let (hasFaces, hasNewFaces) = await detectAndCheckFaceDiversity(currentImage)
            
            await MainActor.run {
                let currentFaceCount = self.detectedFaces.count
                
                // Only update UI if we detected faces and something changed
                if hasFaces && currentFaceCount > 0 {
                    // Update UI even if same faces (user might have moved to new frame with clearer view)
                    self.facesCollectionView.reloadData()
                    self.updateFacesVisibility()
                    
                    // Auto-select first face if none selected or selection is invalid
                    if self.currentFaceIndex >= currentFaceCount {
                        self.currentFaceIndex = 0
                        self.facesCollectionView.selectItem(
                            at: IndexPath(item: 0, section: 0),
                            animated: true,
                            scrollPosition: .centeredHorizontally
                        )
                    }
                    
                    if currentFaceCount != previousFaceCount {
                        print("✅ Detected \(currentFaceCount) faces (was \(previousFaceCount))")
                    }
                } else {
                    // No faces detected, hide the UI
                    self.updateFacesVisibility()
                }
            }
        }
    }
    
    private func setupView() {
        view.backgroundColor = .systemBackground
        
        // Add main content to view (title and subtitle removed to save space)
        view.addSubview(photoContainerView)
        view.addSubview(nameTextField)
        view.addSubview(nameSuggestionsTableView)
        view.addSubview(photoCarouselCollectionView)
        view.addSubview(carouselLeftFadeView)
        view.addSubview(carouselRightFadeView)
        view.addSubview(carouselLeadingTapOverlay)
        view.addSubview(carouselButtonsStackView)

        // Liquid glass Next button (magnifying glass or loading spinner)
        let nextButtonView = LiquidGlassNextButtonView(isLoading: isLoadingNextPhoto, action: { [weak self] in self?.nextPhotoTapped() })
        let nextHosting = UIHostingController(rootView: nextButtonView)
        nextHosting.view.translatesAutoresizingMaskIntoConstraints = false
        nextHosting.view.backgroundColor = .clear
        addChild(nextHosting)
        nextHosting.didMove(toParent: self)
        nextButtonContainerView.addSubview(nextHosting.view)
        nextButtonHostingController = nextHosting
        NSLayoutConstraint.activate([
            nextHosting.view.topAnchor.constraint(equalTo: nextButtonContainerView.topAnchor),
            nextHosting.view.leadingAnchor.constraint(equalTo: nextButtonContainerView.leadingAnchor),
            nextHosting.view.trailingAnchor.constraint(equalTo: nextButtonContainerView.trailingAnchor),
            nextHosting.view.bottomAnchor.constraint(equalTo: nextButtonContainerView.bottomAnchor),
        ])
        
        // Add photo/video content to container
        photoContainerView.addSubview(photoImageView)
        photoContainerView.addSubview(videoPlayerView)
        
        // Add video controls FIRST (so they're below in z-order)
        photoContainerView.addSubview(videoControlsContainer)
        
        // Add controls to container
        videoControlsContainer.addSubview(playPauseButton)
        videoControlsContainer.addSubview(videoProgressSlider)
        
        // Add faces collection view ON TOP of controls
        photoContainerView.addSubview(facesCollectionView)
        // Magnifying glass (Next) at same height as detected faces, on the left side of the faces strip
        photoContainerView.addSubview(nextButtonContainerView)
        
        // Add close button ON TOP of photo (liquid glass circle, same as ContactDetailsView)
        let closeButtonView = LiquidGlassCloseButton { [weak self] in self?.closeTapped() }
        let closeHosting = UIHostingController(rootView: closeButtonView)
        closeHosting.view.translatesAutoresizingMaskIntoConstraints = false
        closeHosting.view.backgroundColor = .clear
        addChild(closeHosting)
        closeHosting.didMove(toParent: self)
        photoContainerView.addSubview(closeHosting.view)
        closeButtonHostingController = closeHosting
        
        // Layout: photo fills space above carousel when keyboard is not shown; bottom stack pinned to safe area
        NSLayoutConstraint.activate([
            // Photo/video container - fills from top down to carousel (no fixed height)
            photoContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            photoContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            photoContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            photoContainerView.bottomAnchor.constraint(equalTo: photoCarouselCollectionView.topAnchor, constant: -12),
            
            // Close button overlaying top-right of photo (44×44 liquid glass circle)
            closeHosting.view.topAnchor.constraint(equalTo: photoContainerView.topAnchor, constant: 12),
            closeHosting.view.trailingAnchor.constraint(equalTo: photoContainerView.trailingAnchor, constant: -12),
            closeHosting.view.widthAnchor.constraint(equalToConstant: 44),
            closeHosting.view.heightAnchor.constraint(equalToConstant: 44),
            
            // Photo image view fills container
            photoImageView.topAnchor.constraint(equalTo: photoContainerView.topAnchor),
            photoImageView.leadingAnchor.constraint(equalTo: photoContainerView.leadingAnchor),
            photoImageView.trailingAnchor.constraint(equalTo: photoContainerView.trailingAnchor),
            photoImageView.bottomAnchor.constraint(equalTo: photoContainerView.bottomAnchor),
            
            // Video player view fills container
            videoPlayerView.topAnchor.constraint(equalTo: photoContainerView.topAnchor),
            videoPlayerView.leadingAnchor.constraint(equalTo: photoContainerView.leadingAnchor),
            videoPlayerView.trailingAnchor.constraint(equalTo: photoContainerView.trailingAnchor),
            videoPlayerView.bottomAnchor.constraint(equalTo: photoContainerView.bottomAnchor),
            
            // Faces strip from leading; magnifying glass (Next) on the right at same height
            facesCollectionView.leadingAnchor.constraint(equalTo: photoContainerView.leadingAnchor),
            facesCollectionView.trailingAnchor.constraint(equalTo: nextButtonContainerView.leadingAnchor, constant: -8),
            facesCollectionView.heightAnchor.constraint(equalToConstant: 68),
            nextButtonContainerView.trailingAnchor.constraint(equalTo: photoContainerView.trailingAnchor),
            nextButtonContainerView.centerYAnchor.constraint(equalTo: facesCollectionView.centerYAnchor),
            nextButtonContainerView.widthAnchor.constraint(equalToConstant: 44),
            nextButtonContainerView.heightAnchor.constraint(equalToConstant: 44),
            
            // Video controls at the very bottom (below faces) - more compact iOS style
            videoControlsContainer.leadingAnchor.constraint(equalTo: photoContainerView.leadingAnchor, constant: 8),
            videoControlsContainer.trailingAnchor.constraint(equalTo: photoContainerView.trailingAnchor, constant: -8),
            videoControlsContainer.bottomAnchor.constraint(equalTo: photoContainerView.bottomAnchor, constant: -8),
            videoControlsContainer.heightAnchor.constraint(equalToConstant: 40),
            
            // Play/pause button on left - more compact
            playPauseButton.leadingAnchor.constraint(equalTo: videoControlsContainer.leadingAnchor, constant: 10),
            playPauseButton.centerYAnchor.constraint(equalTo: videoControlsContainer.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 28),
            playPauseButton.heightAnchor.constraint(equalToConstant: 28),
            
            // Progress slider fills remaining space with less padding
            videoProgressSlider.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 10),
            videoProgressSlider.trailingAnchor.constraint(equalTo: videoControlsContainer.trailingAnchor, constant: -10),
            videoProgressSlider.centerYAnchor.constraint(equalTo: videoControlsContainer.centerYAnchor),
            
            // Photo carousel: fixed height and horizontal; vertical position set by carouselBottomToButtonsTopConstraint (when name hidden) or name section (when visible)
            photoCarouselCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            photoCarouselCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            photoCarouselCollectionView.heightAnchor.constraint(equalToConstant: 72),
            
            // Fade effects on carousel edges
            carouselLeftFadeView.topAnchor.constraint(equalTo: photoCarouselCollectionView.topAnchor),
            carouselLeftFadeView.leadingAnchor.constraint(equalTo: photoCarouselCollectionView.leadingAnchor),
            carouselLeftFadeView.bottomAnchor.constraint(equalTo: photoCarouselCollectionView.bottomAnchor),
            carouselLeftFadeView.widthAnchor.constraint(equalToConstant: 40),
            
            carouselRightFadeView.topAnchor.constraint(equalTo: photoCarouselCollectionView.topAnchor),
            carouselRightFadeView.trailingAnchor.constraint(equalTo: photoCarouselCollectionView.trailingAnchor),
            carouselRightFadeView.bottomAnchor.constraint(equalTo: photoCarouselCollectionView.bottomAnchor),
            carouselRightFadeView.widthAnchor.constraint(equalToConstant: 40),
            
            carouselLeadingTapOverlay.topAnchor.constraint(equalTo: photoCarouselCollectionView.topAnchor),
            carouselLeadingTapOverlay.leadingAnchor.constraint(equalTo: photoCarouselCollectionView.leadingAnchor),
            carouselLeadingTapOverlay.bottomAnchor.constraint(equalTo: photoCarouselCollectionView.bottomAnchor),
            carouselLeadingTapOverlay.widthAnchor.constraint(equalToConstant: 44),
            
            // Name input section below carousel (shown with animation when faces detected)
            nameTextField.topAnchor.constraint(equalTo: photoCarouselCollectionView.bottomAnchor, constant: 12),
            nameTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            nameTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Contact suggestions below name field (same autocompletion as QuickInputView)
            nameSuggestionsTableView.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: 4),
            nameSuggestionsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            nameSuggestionsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            // Spacer row (top pinned by carouselToButtonsConstraint or nameSectionToButtonsConstraint)
            carouselButtonsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            carouselButtonsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            carouselButtonsStackView.heightAnchor.constraint(equalToConstant: 44),
            carouselButtonsStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])

        let inputRowHeight: CGFloat = 56
        nameTextFieldHeightConstraint = nameTextField.heightAnchor.constraint(equalToConstant: inputRowHeight)
        nameTextFieldHeightConstraint?.isActive = true
        nameSuggestionsTableHeightConstraint = nameSuggestionsTableView.heightAnchor.constraint(equalToConstant: 0)
        nameSuggestionsTableHeightConstraint?.isActive = true
        carouselToButtonsConstraint = carouselButtonsStackView.topAnchor.constraint(equalTo: photoCarouselCollectionView.bottomAnchor, constant: 12)
        nameSectionToButtonsConstraint = carouselButtonsStackView.topAnchor.constraint(equalTo: nameSuggestionsTableView.bottomAnchor, constant: 12)
        carouselBottomToButtonsTopConstraint = photoCarouselCollectionView.bottomAnchor.constraint(equalTo: carouselButtonsStackView.topAnchor, constant: -12)
        if useQuickInputForName {
            carouselToButtonsConstraint?.isActive = true
            nameSectionToButtonsConstraint?.isActive = false
            carouselBottomToButtonsTopConstraint?.isActive = false
            nameTextField.isHidden = true
            nameSuggestionsTableView.isHidden = true
        } else {
            carouselToButtonsConstraint?.isActive = false
            nameSectionToButtonsConstraint?.isActive = true
            carouselBottomToButtonsTopConstraint?.isActive = false
            nameTextField.isHidden = false
            nameSuggestionsTableView.isHidden = true
        }
        
        // Create both bottom constraints for faces collection but don't activate yet
        // For videos: position above video controls
        facesBottomConstraintForVideo = facesCollectionView.bottomAnchor.constraint(
            equalTo: videoControlsContainer.topAnchor, 
            constant: -8
        )
        
        // For images: position at bottom of container with padding
        facesBottomConstraintForImage = facesCollectionView.bottomAnchor.constraint(
            equalTo: photoContainerView.bottomAnchor, 
            constant: -12
        )
        
        // Start with image constraint (will be switched when video loads)
        facesBottomConstraintForImage?.isActive = true
        
        // Initially hide faces collection until faces are detected
        facesCollectionView.isHidden = true
    }

    private func archiveAssetFromCarousel(_ asset: PHAsset, atIndex index: Int) {
        var ids = UserDefaults.standard.stringArray(forKey: Self.archivedAssetIDsKey) ?? []
        let id = asset.localIdentifier
        guard !ids.contains(id) else { return }
        ids.append(id)
        UserDefaults.standard.set(ids, forKey: Self.archivedAssetIDsKey)
        UserDefaults.standard.set(true, forKey: Self.cacheInvalidatedKey)
        let deletedPhoto = DeletedPhoto(assetLocalIdentifier: id, deletedDate: Date())
        modelContext.insert(deletedPhoto)
        try? modelContext.save()

        prioritizedAssets.remove(at: index)
        carouselThumbnails.remove(at: index)
        thumbnailLoadingTasks[index]?.cancel()
        var newThumbTasks: [Int: Task<Void, Never>] = [:]
        for (k, task) in thumbnailLoadingTasks {
            if k < index { newThumbTasks[k] = task }
            else if k > index { newThumbTasks[k - 1] = task }
        }
        thumbnailLoadingTasks = newThumbTasks

        var newCached: [Int: UIImage] = [:]
        for (key, img) in cachedDisplayImages {
            if key < index { newCached[key] = img }
            else if key > index { newCached[key - 1] = img }
        }
        cachedDisplayImages = newCached

        if currentCarouselIndex == index {
            currentCarouselIndex = clampCarouselIndex(index)
        } else if currentCarouselIndex > index {
            currentCarouselIndex -= 1
        }

        photoQueue.removeAll { $0.index == index }
        photoQueue = photoQueue.map { c in
            if c.index > index { return PhotoCandidate(asset: c.asset, faceCount: c.faceCount, index: c.index - 1) }
            return c
        }
        if currentBatchIndex > index {
            currentBatchIndex -= 1
        }

        lastCachedDisplayWindow = nil
        lastCarouselThumbnailWindow = nil

        if prioritizedAssets.isEmpty {
            photoCarouselCollectionView.reloadData()
            currentPhotoData = nil
            photoImageView.image = nil
            detectedFaces = []
            faceAssignments = []
            facesCollectionView.reloadData()
        } else {
            let deletePath = IndexPath(item: index, section: 0)
            let targetIndex = currentCarouselIndex
            isProgrammaticallyScrollingCarousel = true
            carouselSelectionVisible = false
            photoCarouselCollectionView.performBatchUpdates({
                photoCarouselCollectionView.deleteItems(at: [deletePath])
            }) { [weak self] _ in
                guard let self = self else { return }
                self.view.layoutIfNeeded()
                self.photoCarouselCollectionView.layoutIfNeeded()
                let path = IndexPath(item: targetIndex, section: 0)
                self.photoCarouselCollectionView.scrollToItem(at: path, at: .centeredHorizontally, animated: false)
                self.carouselSelectionVisible = true
                self.isProgrammaticallyScrollingCarousel = false
                self.photoCarouselCollectionView.reloadItems(at: [path])
                self.loadPhotoAtCarouselIndex(targetIndex)
                self.startCachingDisplayImages(around: targetIndex)
            }
        }
        saveCarouselPosition()
        onPrioritizedAssetsDidChange?(prioritizedAssets)
    }

    /// Defer preprocessing so initial display paints smoothly (avoids launch jank).
    private func deferPreprocessNextBatch() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.preprocessNextBatch()
        }
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
            // If user has jumped ahead in the carousel, skip to that batch
            // This ensures we're always preprocessing photos ahead of the current position
            let adjustedStartIndex = max(currentBatchIndex, currentCarouselIndex + 1)
            
            // If we need to skip batches, update currentBatchIndex
            if adjustedStartIndex > currentBatchIndex {
                await MainActor.run {
                    // Align to batch boundary for cleaner processing
                    self.currentBatchIndex = (adjustedStartIndex / self.batchSize) * self.batchSize
                    print("🔄 Adjusted batch index to \(self.currentBatchIndex) based on carousel position \(self.currentCarouselIndex)")
                }
            }
            
            let startIndex = await MainActor.run { self.currentBatchIndex }
            let endIndex = min(startIndex + batchSize, prioritizedAssets.count)
            let slice = prioritizedAssets[startIndex..<endIndex]
            // Only images: skip videos to speed up search (no frame extraction or face count on video)
            let batchAssets = slice.enumerated().compactMap { offset, asset -> (Int, PHAsset)? in
                asset.mediaType == .image ? (startIndex + offset, asset) : nil
            }
            
            print("📦 Preprocessing batch \(startIndex)..<\(endIndex) (\(batchAssets.count) images, \(slice.count - batchAssets.count) videos skipped)")
            
            var candidates: [PhotoCandidate] = []
            let concurrencyLimit = 4
            for chunkStart in stride(from: 0, to: batchAssets.count, by: concurrencyLimit) {
                let chunk = Array(batchAssets[chunkStart..<min(chunkStart + concurrencyLimit, batchAssets.count)])
                await withTaskGroup(of: PhotoCandidate?.self) { group in
                    for (realIndex, asset) in chunk {
                        group.addTask {
                            guard let image = await self.loadImageForPreprocessing(for: asset) else { return nil }
                            let faceCount = await self.countFaces(in: image)
                            if faceCount >= 2 {
                                return PhotoCandidate(asset: asset, faceCount: faceCount, index: realIndex)
                            }
                            return nil
                        }
                    }
                    for await result in group {
                        if let c = result { candidates.append(c) }
                    }
                }
            }
            
            await MainActor.run {
                self.photoQueue.append(contentsOf: candidates.sorted())
                self.currentBatchIndex = endIndex
                self.isPreprocessing = false
                
                if candidates.isEmpty {
                    print("⚠️ Batch \(startIndex)..<\(endIndex) complete: NO photos with 2+ faces found")
                    print("   Queue size: \(self.photoQueue.count) photos, Reached: \(endIndex)/\(self.prioritizedAssets.count)")
                } else {
                    print("✅ Batch \(startIndex)..<\(endIndex) complete: Found \(candidates.count) photos with faces")
                    print("   2-5 faces: \(candidates.filter { $0.faceCount >= 2 && $0.faceCount <= 5 }.count)")
                    print("   6+ faces: \(candidates.filter { $0.faceCount > 5 }.count)")
                    print("   Queue now has \(self.photoQueue.count) photos total")
                }
                
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
    
    private func cleanupQueueBehindCurrentPosition() {
        let beforeCount = photoQueue.count
        photoQueue.removeAll { candidate in
            candidate.index <= currentCarouselIndex
        }
        let afterCount = photoQueue.count
        
        if beforeCount != afterCount {
            print("🧹 Queue cleanup: removed \(beforeCount - afterCount) photos behind position \(currentCarouselIndex). Remaining: \(afterCount)")
        }
    }
    
    private func startCachingDisplayImages(around centerIndex: Int) {
        guard carouselItemCount > 0 else { return }
        // Apple Photos pattern: Use PHCachingImageManager to prepare images for instant display
        let startIndex = max(0, centerIndex - cacheWindowSize)
        let endIndex = min(carouselItemCount - 1, centerIndex + cacheWindowSize)
        guard startIndex <= endIndex else { return }
        
        // Stop caching for assets that left the window (proper PH API; frees memory and request slots).
        if let last = lastCachedDisplayWindow {
            var toStop: [PHAsset] = []
            for i in last.start...last.end {
                if (i < startIndex || i > endIndex), isValidCarouselIndex(i) {
                    toStop.append(prioritizedAssets[i])
                }
            }
            if !toStop.isEmpty {
                imageManager.stopCachingImages(
                    for: toStop,
                    targetSize: displayImageSize,
                    contentMode: .aspectFill,
                    options: displayImageOptions()
                )
            }
        }
        lastCachedDisplayWindow = (startIndex, endIndex)
        
        // #region agent log
        let thumbLoaded = carouselThumbnails.lazy.filter { $0 != nil }.count
        debugSessionLog(location: "WelcomeFaceNamingVC:startCachingDisplayImages", message: "Cache window update", data: ["cachedDisplayCount": cachedDisplayImages.count, "thumbLoadedCount": thumbLoaded, "centerIndex": centerIndex], hypothesisId: "H4")
        // #endregion
        var assetsToCache: [PHAsset] = []
        for i in startIndex...endIndex {
            assetsToCache.append(prioritizedAssets[i])
        }
        imageManager.startCachingImages(
            for: assetsToCache,
            targetSize: displayImageSize,
            contentMode: .aspectFill,
            options: displayImageOptions()
        )
        
        for i in startIndex...endIndex {
            guard isValidCarouselIndex(i) else { continue }
            if cachedDisplayImages[i] != nil { continue }
            let asset = prioritizedAssets[i]
            let cacheKey = CacheKeyGenerator.key(for: asset, size: displayImageSize)
            if let cached = imageCache.image(for: cacheKey) {
                cachedDisplayImages[i] = cached
                continue
            }
            let options = displayImageOptions()
            imageManager.requestImage(
                for: asset,
                targetSize: displayImageSize,
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, info in
                guard let self = self, let image = image else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true
                Task {
                    let decoded = await ImageDecodingService.decodeForDisplay(image)
                    let toStore = decoded ?? image
                    await MainActor.run {
                        // Never overwrite a higher-fidelity image with a lower-fidelity one.
                        // With opportunistic delivery, we may get degraded first then full (or out of order).
                        if isDegraded {
                            if self.cachedDisplayImages[i] == nil {
                                self.cachedDisplayImages[i] = toStore
                                // Do not store degraded in ImageCacheService; wait for full-quality so we don't overwrite.
                            }
                        } else {
                            self.imageCache.setImage(toStore, for: cacheKey)
                            self.cachedDisplayImages[i] = toStore
                        }
                    }
                }
            }
        }
        
        // Evict only far-outside-window images to free memory (keep a buffer so fast swipe-back has images)
        let keysToRemove = cachedDisplayImages.keys.filter { index in
            index < startIndex - displayCacheBuffer || index > endIndex + displayCacheBuffer
        }
        for key in keysToRemove {
            cachedDisplayImages.removeValue(forKey: key)
        }
        // Evict carousel thumbnails far from center so we don't accumulate hundreds as user scrolls 45k items. Phone uses tighter margin for memory.
        let thumbMargin = UIDevice.current.userInterfaceIdiom == .phone ? 30 : 50
        let thumbLow = max(0, centerIndex - thumbMargin)
        let thumbHigh = min(carouselItemCount - 1, centerIndex + thumbMargin)
        for i in 0..<carouselItemCount where (i < thumbLow || i > thumbHigh) && carouselThumbnails[i] != nil {
            carouselThumbnails[i] = nil
        }
        
        // Carousel strip: preheat thumbnails via PHCachingImageManager so strip scrolling is smooth and requests hit cache
        startCachingCarouselThumbnails(around: centerIndex)
        lastEvictionCenterIndex = centerIndex
    }
    
    /// PHCachingImageManager preheat for the carousel strip. Uses a bounded window and stopCaching when the window moves to avoid unbounded memory use.
    private func startCachingCarouselThumbnails(around centerIndex: Int) {
        guard carouselItemCount > 0 else { return }
        let stripStart = max(0, centerIndex - stripCacheWindowSize)
        let stripEnd = min(carouselItemCount - 1, centerIndex + stripCacheWindowSize)
        guard stripStart <= stripEnd else { return }
        
        if let last = lastCarouselThumbnailWindow {
            var toStop: [PHAsset] = []
            for i in last.start...last.end {
                if (i < stripStart || i > stripEnd), isValidCarouselIndex(i) {
                    toStop.append(prioritizedAssets[i])
                }
            }
            if !toStop.isEmpty {
                imageManager.stopCachingImages(
                    for: toStop,
                    targetSize: carouselThumbnailSize,
                    contentMode: .aspectFill,
                    options: carouselThumbnailOptions()
                )
            }
        }
        lastCarouselThumbnailWindow = (stripStart, stripEnd)
        
        var assetsToCache: [PHAsset] = []
        for i in stripStart...stripEnd where isValidCarouselIndex(i) {
            assetsToCache.append(prioritizedAssets[i])
        }
        guard !assetsToCache.isEmpty else { return }
        imageManager.startCachingImages(
            for: assetsToCache,
            targetSize: carouselThumbnailSize,
            contentMode: .aspectFill,
            options: carouselThumbnailOptions()
        )
    }
    
    private func carouselThumbnailOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        return options
    }
    
    private func displayImageOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        // Opportunistic: first delivery is fast (often local/degraded), second is full quality — instant scroll.
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        return options
    }
    
    private func prefetchAdjacentImages(around centerIndex: Int) {
        startCachingDisplayImages(around: centerIndex)
    }

    // MARK: - Sliding window (fetch more when user scrolls near end/start; keeps memory bounded, no cap on how far back)

    private func slideWindowForwardIfNeeded(centerIndex: Int) {
        guard !isSlidingWindow, carouselItemCount >= slideTriggerMargin, centerIndex >= carouselItemCount - slideTriggerMargin else { return }
        guard let lastDate = prioritizedAssets.last?.creationDate else { return }
        isSlidingWindow = true
        Task {
            let newBatch = await NameFacesCarouselAssetFetcher.fetchAssetsOlderThan(lastDate, limit: slideWindowChunk)
            await MainActor.run {
                defer { isSlidingWindow = false }
                guard !newBatch.isEmpty else { return }
                let oldCount = prioritizedAssets.count
                let oldCenter = currentCarouselIndex
                let dropCount = min(slideWindowChunk, oldCount)
                let deletePaths = (0..<dropCount).map { IndexPath(item: $0, section: 0) }
                let insertPaths = (oldCount - dropCount..<oldCount - dropCount + newBatch.count).map { IndexPath(item: $0, section: 0) }
                prioritizedAssets = Array(prioritizedAssets.dropFirst(dropCount)) + newBatch
                carouselThumbnails = Array(carouselThumbnails.dropFirst(dropCount)) + Array(repeating: nil, count: newBatch.count)
                (0..<dropCount).forEach { thumbnailLoadingTasks.removeValue(forKey: $0) }
                thumbnailLoadingTasks.forEach { $0.value.cancel() }
                thumbnailLoadingTasks.removeAll()
                windowStartIndex += dropCount
                currentCarouselIndex = clampCarouselIndex(max(0, oldCenter - dropCount))
                cachedDisplayImages.removeAll()
                lastCachedDisplayWindow = nil
                lastCarouselThumbnailWindow = nil
                lastEvictionCenterIndex = nil
                photoQueue.removeAll()
                // So the new tail (dropped-from-start + new batch) gets preprocessed for magnifying glass
                currentBatchIndex = min(currentBatchIndex, oldCount - dropCount)
                UIView.performWithoutAnimation {
                    photoCarouselCollectionView.performBatchUpdates {
                        photoCarouselCollectionView.deleteItems(at: deletePaths)
                        photoCarouselCollectionView.insertItems(at: insertPaths)
                    }
                }
                scrollCarouselToCurrentIndex()
                loadPhotoAtCarouselIndex(currentCarouselIndex)
                startCachingDisplayImages(around: currentCarouselIndex)
                preprocessNextBatch()
            }
        }
    }

    /// Appends batches (older than last) until the carousel contains the given asset ID, so we can restore to that photo after re-open. Returns true if the asset was found.
    private func fetchUntilSavedAssetPresent(assetID: String) async -> Bool {
        let maxBatches = 10
        for _ in 0..<maxBatches {
            let alreadyThere = await MainActor.run { self.prioritizedAssets.contains { $0.localIdentifier == assetID } }
            if alreadyThere { return true }
            let lastDate = await MainActor.run { self.prioritizedAssets.last?.creationDate }
            guard let lastDate else { return false }
            let newBatch = await NameFacesCarouselAssetFetcher.fetchAssetsOlderThan(lastDate, limit: slideWindowChunk)
            guard !newBatch.isEmpty else { return false }
            await MainActor.run {
                let oldCount = self.prioritizedAssets.count
                self.prioritizedAssets.append(contentsOf: newBatch)
                self.carouselThumbnails.append(contentsOf: Array(repeating: nil, count: newBatch.count))
                self.currentBatchIndex = min(self.currentBatchIndex, oldCount)
                let insertPaths = (oldCount..<self.prioritizedAssets.count).map { IndexPath(item: $0, section: 0) }
                self.photoCarouselCollectionView.insertItems(at: insertPaths)
            }
            let found = await MainActor.run { self.prioritizedAssets.contains { $0.localIdentifier == assetID } }
            if found { return true }
        }
        return false
    }

    /// Fetches more assets (older than current last) and appends to the carousel. Used when magnifying glass
    /// exhausts the queue so "next relevant photo" can be found beyond the current window. Returns true if new assets were appended.
    private func fetchAndAppendMoreAssetsForNextButton() async -> Bool {
        let lastDate = await MainActor.run { self.prioritizedAssets.last?.creationDate }
        guard let lastDate else { return false }
        let newBatch = await NameFacesCarouselAssetFetcher.fetchAssetsOlderThan(lastDate, limit: slideWindowChunk)
        guard !newBatch.isEmpty else { return false }
        return await MainActor.run {
            let oldCount = prioritizedAssets.count
            prioritizedAssets.append(contentsOf: newBatch)
            carouselThumbnails.append(contentsOf: Array(repeating: nil, count: newBatch.count))
            // Preprocessing has run up to currentBatchIndex; the new segment is [oldCount, count), so allow preprocessing from there
            currentBatchIndex = min(currentBatchIndex, oldCount)
            let insertPaths = (oldCount..<prioritizedAssets.count).map { IndexPath(item: $0, section: 0) }
            photoCarouselCollectionView.insertItems(at: insertPaths)
            print("📥 Appended \(newBatch.count) assets for Next button. Carousel now \(prioritizedAssets.count), batch index \(currentBatchIndex)")
            return true
        }
    }

    private func slideWindowBackwardIfNeeded(centerIndex: Int) {
        guard !isSlidingWindow, windowStartIndex > 0, centerIndex < slideTriggerMargin else { return }
        guard let firstDate = prioritizedAssets.first?.creationDate else { return }
        isSlidingWindow = true
        Task {
            let newBatch = await NameFacesCarouselAssetFetcher.fetchAssetsNewerThan(firstDate, limit: slideWindowChunk)
            await MainActor.run {
                defer { isSlidingWindow = false }
                guard !newBatch.isEmpty else { return }
                let oldCount = prioritizedAssets.count
                let oldCenter = currentCarouselIndex
                let dropCount = min(slideWindowChunk, oldCount)
                let deletePaths = (oldCount - dropCount..<oldCount).map { IndexPath(item: $0, section: 0) }
                let insertPaths = (0..<newBatch.count).map { IndexPath(item: $0, section: 0) }
                prioritizedAssets = newBatch + Array(prioritizedAssets.dropLast(dropCount))
                carouselThumbnails = Array(repeating: nil, count: newBatch.count) + Array(carouselThumbnails.dropLast(dropCount))
                (oldCount - dropCount..<oldCount).forEach { thumbnailLoadingTasks.removeValue(forKey: $0) }
                thumbnailLoadingTasks.forEach { $0.value.cancel() }
                thumbnailLoadingTasks.removeAll()
                windowStartIndex = max(0, windowStartIndex - dropCount)
                currentCarouselIndex = clampCarouselIndex(oldCenter + newBatch.count)
                cachedDisplayImages.removeAll()
                lastCachedDisplayWindow = nil
                lastCarouselThumbnailWindow = nil
                lastEvictionCenterIndex = nil
                photoQueue.removeAll()
                // New batch is at 0..<newBatch.count; start preprocessing from the beginning so queue gets new candidates
                currentBatchIndex = 0
                UIView.performWithoutAnimation {
                    photoCarouselCollectionView.performBatchUpdates {
                        photoCarouselCollectionView.insertItems(at: insertPaths)
                        photoCarouselCollectionView.deleteItems(at: deletePaths)
                    }
                }
                scrollCarouselToCurrentIndex()
                loadPhotoAtCarouselIndex(currentCarouselIndex)
                startCachingDisplayImages(around: currentCarouselIndex)
                preprocessNextBatch()
            }
        }
    }

    private func loadNextPhotoWithFaces() {
        guard !isLoadingNextPhoto else {
            print("⚠️ Already loading next photo, skipping")
            return
        }
        isLoadingNextPhoto = true
        updateNextButtonView()
        saveCurrentPhotoAssignmentsToMemory()
        detectedFaces = []
        faceAssignments = []
        faceAssignedExistingContact = [:]
        facesCollectionView.reloadData()
        nameTextField.text = ""
        filterContactsForNameSuggestions()
        updateFacesVisibility()
        
        print("🔄 Starting loadNextPhotoWithFaces from carousel index \(currentCarouselIndex)")
        
        Task {
            let lastShownDate = await MainActor.run { self.currentPhotoData?.date }
            var emptyQueueAttempts = 0
            let maxEmptyQueueAttempts = 10  // Safety limit to prevent infinite loops
            
            while true {
                let atEnd = await MainActor.run { self.currentBatchIndex >= self.prioritizedAssets.count }
                let queueEmpty = await MainActor.run { self.photoQueue.isEmpty }
                
                // If queue is empty and we've reached the end of the current asset list, try to fetch more before giving up
                if queueEmpty && atEnd {
                    let appended = await fetchAndAppendMoreAssetsForNextButton()
                    if appended {
                        emptyQueueAttempts = 0
                        try? await Task.sleep(for: .milliseconds(150))
                        continue
                    }
                    print("🛑 No more assets in library to fetch")
                    break
                }
                
                if queueEmpty {
                    emptyQueueAttempts += 1
                    
                    if emptyQueueAttempts > maxEmptyQueueAttempts {
                        print("❌ Reached max empty queue attempts (\(maxEmptyQueueAttempts)), stopping search")
                        break
                    }
                    
                    print("📭 Queue empty (attempt \(emptyQueueAttempts)/\(maxEmptyQueueAttempts)), preprocessing next batch...")
                    
                    await MainActor.run {
                        self.preprocessNextBatch()
                    }
                    
                    // Preprocessing runs async; wait for queue to fill, batch to finish, or reach end
                    let preprocessWaitStart = ContinuousClock.now
                    let preprocessWaitTimeout: Duration = .seconds(30)
                    let pollInterval: Duration = .milliseconds(150)
                    while true {
                        try? await Task.sleep(for: pollInterval)
                        let state = await MainActor.run { (self.photoQueue.isEmpty, self.currentBatchIndex >= self.prioritizedAssets.count, self.isPreprocessing) }
                        let (nowEmpty, nowAtEnd, stillPreprocessing) = state
                        if !nowEmpty || nowAtEnd || !stillPreprocessing { break }
                        if ContinuousClock.now - preprocessWaitStart > preprocessWaitTimeout { break }
                    }
                    continue
                }
                
                // Reset empty queue counter when we have items
                emptyQueueAttempts = 0
                
                // Remove candidates from queue until we find one that comes AFTER current carousel position
                // This ensures next button always moves forward chronologically, never backwards
                var candidate = photoQueue.removeFirst()
                
                // Skip any photos that are at or before the current carousel position
                while candidate.index <= currentCarouselIndex && !photoQueue.isEmpty {
                    print("⏭️ Skipping photo at index \(candidate.index) (current position: \(currentCarouselIndex))")
                    candidate = photoQueue.removeFirst()
                }
                
                // If we exhausted the queue but still haven't found a forward photo, load next batch or fetch more assets
                if candidate.index <= currentCarouselIndex {
                    let atEnd = await MainActor.run { self.currentBatchIndex >= self.prioritizedAssets.count }
                    if !atEnd {
                        print("⏩ Last candidate (\(candidate.index)) still behind position (\(currentCarouselIndex)), loading next batch")
                        await MainActor.run {
                            self.preprocessNextBatch()
                        }
                        // Wait for batch to complete (preprocessing is async)
                        let waitStart = ContinuousClock.now
                        while ContinuousClock.now - waitStart < .seconds(30) {
                            try? await Task.sleep(for: .milliseconds(150))
                            let state = await MainActor.run { (self.photoQueue.isEmpty, self.currentBatchIndex >= self.prioritizedAssets.count, self.isPreprocessing) }
                            if !state.0 || state.1 || !state.2 { break }
                        }
                        continue
                    }
                    // At end of list; try to fetch more so we can find a forward candidate
                    let appended = await fetchAndAppendMoreAssetsForNextButton()
                    if appended {
                        try? await Task.sleep(for: .milliseconds(150))
                        continue
                    }
                    print("🛑 No more batches to process and no more assets to fetch")
                    break
                }
                
                // Skip photos taken too close in time (e.g. burst/duplicate group shots); use date metadata only (no extra I/O)
                if let last = lastShownDate, let candidateDate = candidate.asset.creationDate {
                    let interval = abs(candidateDate.timeIntervalSince(last))
                    if interval < nextPhotoMinimumTimeInterval {
                        print("⏭️ Skipping photo at index \(candidate.index) (within \(Int(interval))s of previous)")
                        continue
                    }
                }
                
                print("✅ Found candidate at index \(candidate.index) with \(candidate.faceCount) faces")
                
                guard let image = await loadOptimizedImage(for: candidate.asset) else {
                    continue
                }
                
                // Check if this is a video asset
                if candidate.asset.mediaType == .video {
                    let date = candidate.asset.creationDate ?? Date()
                    await MainActor.run {
                        if let assetIndex = self.prioritizedAssets.firstIndex(of: candidate.asset) {
                            self.currentCarouselIndex = assetIndex
                            self.applyMainImage(image, date: date, asset: candidate.asset, forCarouselIndex: assetIndex)
                            self.saveCarouselPosition()
                            self.photoCarouselCollectionView.reloadData()
                            self.isProgrammaticallyScrollingCarousel = true
                            self.carouselSelectionVisible = false
                            self.photoCarouselCollectionView.reloadItems(at: self.photoCarouselCollectionView.indexPathsForVisibleItems)
                            self.photoCarouselCollectionView.scrollToItem(
                                at: IndexPath(item: assetIndex, section: 0),
                                at: .centeredHorizontally,
                                animated: true
                            )
                        }
                        self.isLoadingNextPhoto = false
                        self.updateNextButtonView()
                        self.detectedFaces = []
                        self.faceAssignments = []
                        self.facesCollectionView.reloadData()
                        self.updateFacesVisibility()
                    }
                    // Setup video player
                    await self.setupVideoPlayer(for: candidate.asset)
                    
                    await MainActor.run {
                        if self.photoQueue.count < 10 && !self.isPreprocessing {
                            self.preprocessNextBatch()
                        }
                    }
                    return
                }
                
                // For images, detect faces immediately (full-resolution may differ from preprocessing)
                let (hasFaces, hasNewFaces) = await detectAndCheckFaceDiversity(image)
                let detectedCount = await MainActor.run { self.detectedFaces.count }
                let hasEnoughFaces = detectedCount >= 2
                
                if hasFaces && hasNewFaces && hasEnoughFaces {
                    let date = candidate.asset.creationDate ?? Date()
                    await MainActor.run {
                        if let assetIndex = self.prioritizedAssets.firstIndex(of: candidate.asset) {
                            self.currentCarouselIndex = assetIndex
                            self.applyMainImage(image, date: date, asset: candidate.asset, forCarouselIndex: assetIndex)
                            self.saveCarouselPosition()
                            self.photoCarouselCollectionView.reloadData()
                            self.isProgrammaticallyScrollingCarousel = true
                            self.carouselSelectionVisible = false
                            self.photoCarouselCollectionView.reloadItems(at: self.photoCarouselCollectionView.indexPathsForVisibleItems)
                            self.photoCarouselCollectionView.scrollToItem(
                                at: IndexPath(item: assetIndex, section: 0),
                                at: .centeredHorizontally,
                                animated: true
                            )
                        }
                        self.isLoadingNextPhoto = false
                        self.updateNextButtonView()
                        self.restoreAssignmentsFromMemory(assetIdentifier: candidate.asset.localIdentifier)
                        self.facesCollectionView.reloadData()
                        self.updateFacesVisibility()
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
            
            print("🏁 Reached end of photo search. Queue: \(photoQueue.count), Batch: \(currentBatchIndex)/\(prioritizedAssets.count)")
            
            await MainActor.run {
                self.isLoadingNextPhoto = false
                self.updateNextButtonView()
                // No candidate passed filters (2+ faces, time dedupe, new faces). Do not advance to a random next photo.
                self.showNoMorePhotosAlert()
            }
        }
    }

    private func loadOptimizedImage(for asset: PHAsset, onFirstDelivery: ((UIImage) -> Void)? = nil) async -> UIImage? {
        if asset.mediaType == .video {
            return await extractVideoFrame(from: asset)
        }
        let cacheKey = CacheKeyGenerator.key(for: asset, size: mainDisplayTargetSize)
        if let cached = imageCache.image(for: cacheKey) {
            return cached
        }
        let image = await requestDisplayImageOpportunistic(for: asset, onFirstDelivery: onFirstDelivery)
        guard let image = image else { return nil }
        let decoded = await ImageDecodingService.decodeForDisplay(image)
        let toCache = decoded ?? image
        imageCache.setImage(toCache, for: cacheKey)
        return toCache
    }

    /// Request image at main-display size for sharp full-screen. With opportunistic delivery, Photos often
    /// sends a lower-res image first (degraded), then full quality. Optional onFirstDelivery is called with
    /// that first image so the UI can show it immediately; the method still returns the final image (or 6s fallback).
    private func requestDisplayImageOpportunistic(for asset: PHAsset, onFirstDelivery: ((UIImage) -> Void)? = nil) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var didResume = false
            var lastImage: UIImage?
            var didInvokeFirst = false
            let lock = NSLock()
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            let fallbackWork = DispatchWorkItem { [lock] in
                lock.lock()
                defer { lock.unlock() }
                if !didResume, let image = lastImage {
                    didResume = true
                    continuation.resume(returning: image)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0, execute: fallbackWork)
            imageManager.requestImage(
                for: asset,
                targetSize: mainDisplayTargetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                guard let image = image else { return }
                lastImage = image
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true
                if !didInvokeFirst, let onFirst = onFirstDelivery {
                    didInvokeFirst = true
                    DispatchQueue.main.async { onFirst(image) }
                }
                if !isDegraded {
                    fallbackWork.cancel()
                    didResume = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    /// Load image at small size for preprocessing only (face count). Fast path; not for display.
    private func loadImageForPreprocessing(for asset: PHAsset) async -> UIImage? {
        let cacheKey = CacheKeyGenerator.key(for: asset, size: preprocessingImageSize)
        if let cached = imageCache.image(for: cacheKey) {
            return cached
        }
        return await withCheckedContinuation { continuation in
            var didResume = false
            let lock = NSLock()
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let fallback = DispatchWorkItem { [lock] in
                lock.lock()
                defer { lock.unlock() }
                if !didResume {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: fallback)
            imageManager.requestImage(
                for: asset,
                targetSize: preprocessingImageSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                lock.lock()
                defer { lock.unlock() }
                guard !didResume, let image = image else { return }
                fallback.cancel()
                didResume = true
                self.imageCache.setImage(image, for: cacheKey)
                continuation.resume(returning: image)
            }
        }
    }

    private func setupVideoPlayer(for asset: PHAsset, carouselIndex: Int? = nil) async {
        // Clean up existing player on main thread FIRST
        await MainActor.run {
            cleanupVideoPlayer()
            currentVideoAsset = asset
            print("📹 Setting up custom video player for asset")
        }
        
        // Request the AVAsset for the video
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] playerItem, _ in
                guard let self = self, let playerItem = playerItem else {
                    continuation.resume()
                    return
                }
                
                let indexToCheck = carouselIndex
                DispatchQueue.main.async {
                    if let idx = indexToCheck, self.currentCarouselIndex != idx {
                        continuation.resume()
                        return
                    }
                    // Create player with the item
                    let player = AVPlayer(playerItem: playerItem)
                    player.isMuted = true  // Always muted
                    self.videoPlayer = player
                    
                    // Create player layer — fit (letterbox/pillarbox), same as photos; no cropping
                    let playerLayer = AVPlayerLayer(player: player)
                    playerLayer.videoGravity = AVLayerVideoGravity.resizeAspect
                    playerLayer.frame = CGRect(origin: .zero, size: self.videoPlayerView.bounds.size)
                    
                    // Remove old layer if exists
                    self.videoPlayerView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
                    self.videoPlayerView.layer.addSublayer(playerLayer)
                    self.videoPlayerLayer = playerLayer
                    
                    // Show video player, keep controls hidden (shown only when user drags)
                    self.videoPlayerView.isHidden = false
                    self.videoControlsContainer.isHidden = true  // Hidden by default, Apple pattern
                    self.videoControlsContainer.alpha = 0  // Start at 0 for smooth fade-in
                    self.photoImageView.isHidden = true
                    
                    // Position faces at bottom initially (will move up when user drags to scrub)
                    // Apple pattern: Drag on video to scrub AND show controls
                    UIView.performWithoutAnimation {
                        self.facesBottomConstraintForVideo?.isActive = false
                        self.facesBottomConstraintForImage?.isActive = true
                        self.view.layoutIfNeeded()
                    }
                    
                    // Setup time observer for progress slider
                    self.setupTimeObserver()
                    
                    // Start periodic face detection timer
                    self.startFaceDetectionTimer()
                    
                    // Auto-play the video
                    player.play()
                    self.updatePlayPauseButton(isPlaying: true)
                    
                    print("✅ Custom video player ready (muted, auto-playing)")
                    print("   Faces will be detected automatically every \(self.detectionInterval)s while playing")
                    continuation.resume()
                }
            }
        }
    }
    
    private func setupTimeObserver() {
        // Add periodic time observer to update slider
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = videoPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self,
                  !self.isSeekingVideo,
                  let duration = self.videoPlayer?.currentItem?.duration.seconds,
                  duration.isFinite,
                  duration > 0 else {
                return
            }
            
            let currentTime = time.seconds
            self.videoProgressSlider.value = Float(currentTime / duration)
        }
    }
    
    private func startFaceDetectionTimer() {
        stopFaceDetectionTimer()
        
        faceDetectionTimer = Timer.scheduledTimer(
            timeInterval: 0.5,  // Check every 0.5s
            target: self,
            selector: #selector(periodicFaceDetection),
            userInfo: nil,
            repeats: true
        )
    }
    
    private func stopFaceDetectionTimer() {
        faceDetectionTimer?.invalidate()
        faceDetectionTimer = nil
    }
    
    private func cleanupVideoPlayer() {
        stopFaceDetectionTimer()
        cancelControlsAutoHide()  // Clean up controls hide timer
        
        // Remove time observer from the current player before releasing it
        if let observer = timeObserver, let player = videoPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Pause and release player
        videoPlayer?.pause()
        videoPlayer = nil
        
        // Clean up layer
        videoPlayerLayer?.removeFromSuperlayer()
        videoPlayerLayer = nil
        
        // Reset state
        currentVideoAsset = nil
        lastDetectionTime = 0
        isScrubbing = false
        isSeekingVideo = false
        
        // Update UI without animation - hide video elements only
        UIView.performWithoutAnimation {
            videoPlayerView.isHidden = true
            videoControlsContainer.isHidden = true
            videoControlsContainer.alpha = 0  // Reset alpha for next video
            // Don't touch photoImageView.isHidden here - it might already be visible
            // Let the caller handle showing the image view if needed
        }
        
        // DON'T call configureLayoutForImage here - let the caller handle layout changes
        // This prevents redundant layout updates that cause visual jumps
        
        // Reset slider
        videoProgressSlider.value = 0
    }
    
    /// Photos and videos: fit (letterbox/pillarbox if needed); no cropping. Call whenever main image changes.
    private func setMainImageContentMode(for asset: PHAsset) {
        photoImageView.contentMode = .scaleAspectFit
    }
    
    private func captureCurrentVideoFrame() async -> UIImage? {
        guard let player = videoPlayer,
              let currentItem = player.currentItem,
              let asset = currentItem.asset as? AVURLAsset else {
            return nil
        }
        
        let currentTime = player.currentTime()
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = self.detectionTargetSize
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                
                do {
                    let cgImage = try generator.copyCGImage(at: currentTime, actualTime: nil)
                    let image = UIImage(cgImage: cgImage)
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func extractVideoFrame(from asset: PHAsset) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                guard let avAsset = avAsset else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let generator = AVAssetImageGenerator(asset: avAsset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = self.detectionTargetSize
                
                // Extract frame at 1 second (or start if video is shorter)
                let time = CMTime(seconds: 1.0, preferredTimescale: 600)
                
                do {
                    let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                    let image = UIImage(cgImage: cgImage)
                    continuation.resume(returning: image)
                } catch {
                    print("⚠️ Failed to extract video frame: \(error)")
                    continuation.resume(returning: nil)
                }
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
                        // Overlay chips: tighter crop so face reads clearly in small circles
                        let overlayRect = FaceCrop.expandedRect(for: observation, imageSize: imageSize, scale: FaceCrop.overlayScale)
                        // Contact photo: wider crop (saved when user assigns a name)
                        let saveRect = FaceCrop.expandedRect(for: observation, imageSize: imageSize, scale: FaceCrop.contactPhotoScale)
                        
                        if !overlayRect.isNull && !overlayRect.isEmpty,
                           let overlayCrop = cgImage.cropping(to: overlayRect),
                           !saveRect.isNull && !saveRect.isEmpty,
                           let saveCrop = cgImage.cropping(to: saveRect) {
                            
                            let facePrintData = self.generateFacePrint(for: observation, in: cgImage)
                            
                            let isNewFace = self.isFaceNew(facePrint: facePrintData)
                            if isNewFace {
                                hasAtLeastOneNewFace = true
                                if let fpData = facePrintData {
                                    newFacePrints.append(fpData)
                                }
                            }
                            
                            faces.append(DetectedFaceInfo(
                                displayImage: UIImage(cgImage: overlayCrop),
                                image: UIImage(cgImage: saveCrop),
                                boundingBox: saveRect,
                                facePrint: facePrintData
                            ))
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.detectedFaces = faces
                        self.faceAssignments = Array(repeating: "", count: faces.count)
                        
                        print("👤 Detected \(faces.count) faces (new: \(hasAtLeastOneNewFace))")
                        
                        for fpData in newFacePrints {
                            self.recentlyShownFacePrints.append(fpData)
                        }
                        
                        if self.recentlyShownFacePrints.count > self.maxRecentFaces {
                            self.recentlyShownFacePrints.removeFirst(self.recentlyShownFacePrints.count - self.maxRecentFaces)
                        }
                        
                        // Update visibility of faces UI based on whether we found faces
                        self.updateFacesVisibility()
                        
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
    
    /// Updates the Next button to show magnifying glass or loading spinner.
    private func updateNextButtonView() {
        nextButtonHostingController?.rootView = LiquidGlassNextButtonView(
            isLoading: isLoadingNextPhoto,
            action: { [weak self] in self?.nextPhotoTapped() }
        )
    }

    @objc private func nextPhotoTapped() {
        // Prevent rapid tapping that can cause issues
        guard !isLoadingNextPhoto else {
            print("⚠️ Next button tapped while already loading, ignoring")
            return
        }
        
        print("👆 Next button tapped")
        saveCurrentFaces()
        cleanupVideoPlayer()
        loadNextPhotoWithFaces()
    }

    private func saveCurrentFaces() {
        guard let photoData = currentPhotoData else { return }
        
        for (index, name) in faceAssignments.enumerated() {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard index < detectedFaces.count else { continue }
            
            let faceInfo = detectedFaces[index]
            let thumbnailData = jpegDataForStoredFaceThumbnail(faceInfo.image)
            let contactPhotoData = jpegDataForStoredContactPhoto(faceInfo.image)
            
            if let existingContact = faceAssignedExistingContact[index] {
                // Don't replace contact's main photo; store this face as one more image of the contact (FaceEmbedding).
                let embedding = FaceEmbedding(
                    assetIdentifier: "name-faces-\(UUID().uuidString)",
                    contactUUID: existingContact.uuid,
                    photoDate: photoData.date, isManuallyVerified: true, thumbnailData: thumbnailData
                )
                modelContext.insert(embedding)
                totalFacesSaved += 1
            } else {
                let contact = Contact(
                    name: trimmed,
                    summary: "",
                    isMetLongAgo: false,
                    timestamp: photoData.date,
                    notes: [],
                    tags: [],
                    photo: contactPhotoData,
                    group: "",
                    cropOffsetX: 0,
                    cropOffsetY: 0,
                    cropScale: 1.0
                )
                modelContext.insert(contact)
                ImageAccessibleBackground.updateContactPhotoGradient(contact, image: faceInfo.image)
                totalFacesSaved += 1
            }
        }
        
        do {
            try modelContext.save()
            print("✅ Saved \(faceAssignments.filter { !$0.isEmpty }.count) faces from current photo")
        } catch {
            print("❌ Failed to save faces: \(error)")
        }
        
        totalPhotosProcessed += 1
    }
    
    private func saveCurrentFacesAsync() async {
        guard let photoData = await MainActor.run(body: { self.currentPhotoData }) else { return }
        
        let facesToSave = await MainActor.run {
            self.faceAssignments.enumerated().compactMap { (index, name) -> (Int, String, DetectedFaceInfo, Date, Contact?)? in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                guard index < self.detectedFaces.count else { return nil }
                return (index, trimmed, self.detectedFaces[index], photoData.date, self.faceAssignedExistingContact[index])
            }
        }
        
        // Process JPEG compression in background (expensive operation); use storage-sized images to limit app footprint.
        var savedCount = 0
        for (_, name, faceInfo, date, existingContact) in facesToSave {
            let thumbnailData = jpegDataForStoredFaceThumbnail(faceInfo.image)
            let contactPhotoData = jpegDataForStoredContactPhoto(faceInfo.image)
            
            await MainActor.run {
                if let existing = existingContact {
                    // Don't replace contact's main photo; store this face as one more image of the contact (FaceEmbedding).
                    let embedding = FaceEmbedding(
                        assetIdentifier: "name-faces-\(UUID().uuidString)",
                        contactUUID: existing.uuid,
                        photoDate: date, isManuallyVerified: true, thumbnailData: thumbnailData
                    )
                    self.modelContext.insert(embedding)
                    self.totalFacesSaved += 1
                    savedCount += 1
                } else {
                    let contact = Contact(
                        name: name,
                        summary: "",
                        isMetLongAgo: false,
                        timestamp: date,
                        notes: [],
                        tags: [],
                        photo: contactPhotoData,
                        group: "",
                        cropOffsetX: 0,
                        cropOffsetY: 0,
                        cropScale: 1.0
                    )
                    self.modelContext.insert(contact)
                    ImageAccessibleBackground.updateContactPhotoGradient(contact, image: faceInfo.image)
                    self.totalFacesSaved += 1
                    savedCount += 1
                }
            }
        }
        
        await MainActor.run {
            do {
                try self.modelContext.save()
                print("✅ Saved \(savedCount) faces from current photo")
            } catch {
                print("❌ Failed to save faces: \(error)")
            }
            
            self.totalPhotosProcessed += 1
        }
    }
    
    /// Shown when user taps magnifying glass but is already at the last photo. Informational only; does not dismiss the view.
    private func showNoMorePhotosAlert() {
        saveCurrentFaces()
        let alert = UIAlertController(
            title: "No More Photos",
            message: "No more photos to be found. You can keep naming faces on this photo or close when you're done.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
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
            // Clear saved position since user completed the flow
            self.clearSavedPosition()
            self.delegate?.welcomeFaceNamingViewControllerDidFinish(self)
        })
        
        present(alert, animated: true)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }
    
    private func loadInitialCarouselThumbnails() {
        // Native-first: fewer initial thumbnails on phone so main photo and carousel appear faster.
        let cap = (UIDevice.current.userInterfaceIdiom == .phone) ? 15 : 30
        let initialCount = min(cap, carouselItemCount)
        
        for i in 0..<initialCount {
            loadThumbnailAtIndex(i)
        }
    }
    
    private func loadThumbnailAtIndex(_ index: Int) {
        guard isValidCarouselIndex(index) else { return }
        guard carouselThumbnails[index] == nil else { return } // Already loaded or loading
        
        // Cancel any existing task for this index
        thumbnailLoadingTasks[index]?.cancel()
        
        let task = Task {
            let asset = prioritizedAssets[index]
            if let thumbnail = await loadThumbnailImage(for: asset) {
                await MainActor.run {
                    guard self.isValidCarouselIndex(index) else { return }
                    self.carouselThumbnails[index] = thumbnail
                    
                    // Reload just this cell if visible
                    let indexPath = IndexPath(item: index, section: 0)
                    if self.photoCarouselCollectionView.indexPathsForVisibleItems.contains(indexPath) {
                        self.photoCarouselCollectionView.reloadItems(at: [indexPath])
                    }
                }
            }
            
            await MainActor.run {
                self.thumbnailLoadingTasks.removeValue(forKey: index)
            }
        }
        
        thumbnailLoadingTasks[index] = task
    }
    
    private func loadVisibleAndNearbyThumbnails() {
        let visibleIndexPaths = photoCarouselCollectionView.indexPathsForVisibleItems
        let visibleIndices = visibleIndexPaths.map { $0.item }
        
        guard let minVisible = visibleIndices.min(), let maxVisible = visibleIndices.max() else { return }
        
        // Load visible thumbnails plus 10 on each side for smooth scrolling
        let startIndex = max(0, minVisible - 10)
        let endIndex = carouselItemCount > 0 ? min(carouselItemCount - 1, maxVisible + 10) : -1
        guard endIndex >= startIndex else { return }
        
        for i in startIndex...endIndex {
            loadThumbnailAtIndex(i)
        }
    }
    
    private func loadThumbnailImage(for asset: PHAsset) async -> UIImage? {
        if asset.mediaType == .video {
            return await loadVideoThumbnail(for: asset)
        }
        let cacheKey = CacheKeyGenerator.key(for: asset, size: carouselThumbnailSize)
        if let cached = imageCache.image(for: cacheKey) {
            return cached
        }
        let image = await requestThumbnailImage(for: asset, size: carouselThumbnailSize)
        guard let image = image else { return nil }
        let decoded = await ImageDecodingService.decodeForDisplay(image)
        let toCache = decoded ?? image
        imageCache.setImage(toCache, for: cacheKey)
        return toCache
    }

    private func requestThumbnailImage(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            var didResume = false
            let lock = NSLock()
            imageManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true
                if !isDegraded || image != nil {
                    didResume = true
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    private func loadVideoThumbnail(for asset: PHAsset) async -> UIImage? {
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            
            imageManager.requestImage(
                for: asset,
                targetSize: carouselThumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    private func jumpToPhotoAtIndex(_ index: Int) {
        guard isValidCarouselIndex(index) else { return }
        
        saveCurrentFaces()
        mainImageLoadTask?.cancel()
        currentCarouselIndex = index
        saveCarouselPosition()
        
        photoQueue.removeAll { candidate in candidate.index <= index }
        print("🧹 Cleaned queue after jump to index \(index). Remaining: \(photoQueue.count) photos")
        
        photoCarouselCollectionView.reloadData()
        isProgrammaticallyScrollingCarousel = true
        carouselSelectionVisible = false
        photoCarouselCollectionView.reloadItems(at: photoCarouselCollectionView.indexPathsForVisibleItems)
        photoCarouselCollectionView.scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: .centeredHorizontally,
            animated: true
        )
        
        mainImageLoadTask = Task {
            let asset = prioritizedAssets[index]
            
            if asset.mediaType == .video {
                guard let image = await loadOptimizedImage(for: asset) else {
                    await MainActor.run { self.mainImageLoadTask = nil }
                    return
                }
                let date = asset.creationDate ?? Date()
                await MainActor.run {
                    self.applyMainImage(image, date: date, asset: asset, forCarouselIndex: index)
                    self.detectedFaces = []
                    self.faceAssignments = []
                    self.facesCollectionView.reloadData()
                    self.updateFacesVisibility()
                }
                let stillShowing = await MainActor.run { self.currentCarouselIndex == index }
                guard stillShowing else {
                    await MainActor.run { self.mainImageLoadTask = nil }
                    return
                }
                await self.setupVideoPlayer(for: asset, carouselIndex: index)
                await MainActor.run { self.mainImageLoadTask = nil }
                return
            }
            
            let date = asset.creationDate ?? Date()
            let cachedImage = await MainActor.run { self.cachedDisplayImages[index] }
            let thumbnailPlaceholder = await MainActor.run {
                self.isValidCarouselIndex(index) ? self.carouselThumbnails[index] : nil
            }
            var imageForDetection: UIImage?
            if let cached = cachedImage {
                imageForDetection = cached
                await MainActor.run {
                    self.applyMainImage(cached, date: date, asset: asset, forCarouselIndex: index)
                }
            } else {
                if let thumb = thumbnailPlaceholder {
                    await MainActor.run {
                        self.applyMainImage(thumb, date: date, asset: asset, forCarouselIndex: index)
                    }
                }
                let onFirst: (UIImage) -> Void = { [weak self] img in
                    guard let self = self else { return }
                    self.applyMainImage(img, date: date, asset: asset, forCarouselIndex: index)
                }
                guard let loadedImage = await loadOptimizedImage(for: asset, onFirstDelivery: onFirst) else {
                    await MainActor.run { self.mainImageLoadTask = nil }
                    return
                }
                imageForDetection = loadedImage
                await MainActor.run {
                    self.applyMainImage(loadedImage, date: date, asset: asset, forCarouselIndex: index)
                }
            }
            guard let image = imageForDetection else {
                await MainActor.run { self.mainImageLoadTask = nil }
                return
            }
            let (_, _) = await detectAndCheckFaceDiversity(image)
            
            await MainActor.run {
                guard self.currentCarouselIndex == index else { return }
                self.restoreAssignmentsFromMemory(assetIdentifier: asset.localIdentifier)
                self.facesCollectionView.reloadData()
                self.updateFacesVisibility()
                if !self.detectedFaces.isEmpty {
                    self.currentFaceIndex = 0
                    self.facesCollectionView.selectItem(
                        at: IndexPath(item: 0, section: 0),
                        animated: false,
                        scrollPosition: .centeredHorizontally
                    )
                }
                self.mainImageLoadTask = nil
            }
        }
    }
    
    /// Persist current photo's face assignments so we can restore when the user returns to this photo.
    private func saveCurrentPhotoAssignmentsToMemory() {
        guard let asset = currentPhotoData?.asset, !faceAssignments.isEmpty else { return }
        var contactUUIDsByIndex: [Int: UUID] = [:]
        for (index, contact) in faceAssignedExistingContact {
            contactUUIDsByIndex[index] = contact.uuid
        }
        NameFacesMemory.setAssignments(
            assetIdentifier: asset.localIdentifier,
            names: faceAssignments,
            contactUUIDsByIndex: contactUUIDsByIndex
        )
    }
    
    /// Restore previously saved face assignments for this photo (names + contact refs). Resolves UUIDs to Contact via modelContext.
    private func restoreAssignmentsFromMemory(assetIdentifier: String) {
        guard !faceAssignments.isEmpty else { return }
        let (names, contactUUIDsByIndex) = NameFacesMemory.getAssignments(assetIdentifier: assetIdentifier, faceCount: faceAssignments.count)
        faceAssignments = names
        faceAssignedExistingContact = [:]
        for (index, uuid) in contactUUIDsByIndex {
            guard index < faceAssignments.count,
                  let contact = fetchContact(by: uuid) else { continue }
            faceAssignedExistingContact[index] = contact
        }
        if currentFaceIndex < faceAssignments.count {
            if useQuickInputForName {
                syncQuickInputWithCurrentFace()
            } else {
                nameTextField.text = faceAssignments[currentFaceIndex]
            }
        }
    }
    
    private func fetchContact(by uuid: UUID) -> Contact? {
        let descriptor = FetchDescriptor<Contact>(predicate: #Predicate<Contact> { contact in contact.uuid == uuid })
        return try? modelContext.fetch(descriptor).first
    }
}

extension WelcomeFaceNamingViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == facesCollectionView {
            return detectedFaces.count
        } else if collectionView == photoCarouselCollectionView {
            return carouselItemCount
        }
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == facesCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FaceCell.reuseIdentifier, for: indexPath) as! FaceCell
            
            let faceInfo = detectedFaces[indexPath.item]
            let assignedName = faceAssignments[indexPath.item]
            let isNamed = !assignedName.isEmpty
            
            cell.configure(with: faceInfo.displayImage, name: assignedName, isNamed: isNamed)
            
            return cell
        } else if collectionView == photoCarouselCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoCarouselCell.reuseIdentifier, for: indexPath) as! PhotoCarouselCell
            
            let thumbnail = carouselThumbnails[indexPath.item]
            // Blue border on centered item; carouselSelectionVisible is false only during programmatic scroll animation
            let isCurrentPhoto = (indexPath.item == currentCarouselIndex) && carouselSelectionVisible
            let isVideo = isValidCarouselIndex(indexPath.item) && prioritizedAssets[indexPath.item].mediaType == .video
            cell.configure(with: thumbnail, isCurrentPhoto: isCurrentPhoto, isVideo: isVideo)
            
            // Load thumbnail if not yet loaded
            if thumbnail == nil {
                loadThumbnailAtIndex(indexPath.item)
            }
            
            return cell
        }
        
        return UICollectionViewCell()
    }
}

extension WelcomeFaceNamingViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        print("🔍 didSelectItemAt called - collection: \(collectionView == facesCollectionView ? "FACES" : "CAROUSEL"), index: \(indexPath.item)")
        
        if collectionView == facesCollectionView {
            print("👆 Face tapped at index \(indexPath.item)")
            
            // Update current face index
            currentFaceIndex = indexPath.item
            
            // Show the name for the selected face in the text field or QuickInput
            if currentFaceIndex < faceAssignments.count {
                if useQuickInputForName {
                    syncQuickInputWithCurrentFace()
                    NotificationCenter.default.post(name: .quickInputRequestFocus, object: nil)
                } else {
                    nameTextField.text = faceAssignments[currentFaceIndex]
                    print("📝 Set text field to: '\(faceAssignments[currentFaceIndex])'")
                    nameTextField.becomeFirstResponder()
                }
            }
            
            // Scroll to center the selected face
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
            
            if !useQuickInputForName {
                // Focus the text field first so keyboard shows immediately; defer filter to avoid blocking
                nameTextField.becomeFirstResponder()
            }
            DispatchQueue.main.async { [weak self] in
                self?.filterContactsForNameSuggestions()
            }
            
            print("✅ Face selection complete: \(currentFaceIndex + 1) of \(detectedFaces.count)")
        } else if collectionView == photoCarouselCollectionView {
            print("📸 Carousel item tapped at index \(indexPath.item)")
            hasUserInteractedWithCarousel = true
            isUserTappingCarousel = true
            jumpToPhotoAtIndex(indexPath.item)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        // Always allow face selection
        if collectionView == facesCollectionView {
            return true
        }
        
        // For carousel, allow selection
        return true
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard collectionView == photoCarouselCollectionView,
              isValidCarouselIndex(indexPath.item) else { return nil }
        let asset = prioritizedAssets[indexPath.item]
        let index = indexPath.item
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let deleteAction = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.archiveAssetFromCarousel(asset, atIndex: index)
            }
            return UIMenu(title: "", children: [deleteAction])
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == photoCarouselCollectionView {
            guard !isProgrammaticallyScrollingCarousel && !isUserTappingCarousel else { return }
            guard hasUserInteractedWithCarousel else { return }
            
            guard let centeredIndex = findCenteredItemIndex(), centeredIndex != currentCarouselIndex else { return }
            
            let previousCenteredIndex = currentCarouselIndex
            currentCarouselIndex = centeredIndex
            
            // Deferred commitment (large-app pattern): don't run saveCarouselPosition or startCachingDisplayImages on every frame. Schedule once for when scroll settles; cancel and reschedule on each scroll so we only commit after 0.12s of no movement.
            scrollCommitWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.commitScrollPosition()
            }
            scrollCommitWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + scrollSettleInterval, execute: workItem)
            
            // When a video is playing, hide it immediately so the new centered item shows (don't wait for scroll to stop)
            if videoPlayer != nil {
                cleanupVideoPlayer()
                photoImageView.isHidden = false  // Ensure image view is visible after video is hidden
            }
            
            // Main content: show cached image for the newly centered item (image or video thumbnail). Visual-only; no heavy load.
            if isValidCarouselIndex(centeredIndex), let cachedImage = cachedDisplayImages[centeredIndex] {
                let asset = prioritizedAssets[centeredIndex]
                applyMainImage(cachedImage, date: asset.creationDate ?? Date(), asset: asset, forCarouselIndex: centeredIndex)
            }
            
            // Blue border: move selection to the newly centered item (reload only the two cells that changed)
            let pathsToReload = [IndexPath(item: previousCenteredIndex, section: 0), IndexPath(item: centeredIndex, section: 0)]
            UIView.performWithoutAnimation {
                photoCarouselCollectionView.reloadItems(at: pathsToReload)
            }
        }
    }
    
    /// Called when scroll has settled (timer) or ended. Commits current center: save position, update cache window and eviction. Does not run loadPhotoAtCarouselIndex (that runs only on scroll end / tap).
    private func commitScrollPosition() {
        scrollCommitWorkItem = nil
        guard let centeredIndex = findCenteredItemIndex(), isValidCarouselIndex(centeredIndex) else { return }
        currentCarouselIndex = centeredIndex
        saveCarouselPosition()
        startCachingDisplayImages(around: centeredIndex)
        // Do not trigger slide here — only when scroll has ended (performPostScrollUpdates). Avoids out-of-time slides during scroll.
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if scrollView == photoCarouselCollectionView {
            scrollCommitWorkItem?.cancel()
            scrollCommitWorkItem = nil
            mainImageLoadTask?.cancel()
            mainImageLoadTask = nil
            hasUserInteractedWithCarousel = true
            isUserTappingCarousel = false
            isProgrammaticallyScrollingCarousel = false
            hasUserStoppedScrolling = false
            startCachingDisplayImages(around: currentCarouselIndex)
            loadVisibleAndNearbyThumbnails()
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView == photoCarouselCollectionView {
            scrollCommitWorkItem?.cancel()
            scrollCommitWorkItem = nil
            isUserTappingCarousel = false
            hasUserStoppedScrolling = true
            guard hasUserInteractedWithCarousel, let centeredIndex = findCenteredItemIndex() else { return }
            let prev = currentCarouselIndex
            currentCarouselIndex = centeredIndex
            saveCarouselPosition()
            performPostScrollUpdates(for: centeredIndex)
        }
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView == photoCarouselCollectionView && !decelerate {
            scrollCommitWorkItem?.cancel()
            scrollCommitWorkItem = nil
            isUserTappingCarousel = false
            hasUserStoppedScrolling = true
            guard hasUserInteractedWithCarousel, let centeredIndex = findCenteredItemIndex() else { return }
            let prev = currentCarouselIndex
            currentCarouselIndex = centeredIndex
            saveCarouselPosition()
            performPostScrollUpdates(for: centeredIndex)
        }
    }
    
    private func performPostScrollUpdates(for centeredIndex: Int) {
        // All heavy operations happen here, AFTER scrolling stops
        // CRITICAL: Avoid any layout changes that cause visual jumps
        
        // Wrap everything in performWithoutAnimation to prevent any implicit animations
        UIView.performWithoutAnimation {
            // 1. Update carousel thumbnails
            loadVisibleAndNearbyThumbnails()
            
            // 2. Update carousel cell highlights
            photoCarouselCollectionView.reloadData()
            
            // 3. Clean up video player WITHOUT affecting image view
            // Only clean up if we're showing an image (not switching between media types)
            if isValidCarouselIndex(centeredIndex) {
                let asset = prioritizedAssets[centeredIndex]
                
                if asset.mediaType == .video {
                    // Will setup video, cleanup is fine
                    cleanupVideoPlayer()
                    configureLayoutForVideo()  // Ensure faces start at bottom for video
                } else {
                    // Image asset - ensure video is cleaned but DON'T touch image view layout
                    if videoPlayer != nil {
                        cleanupVideoPlayer()
                        configureLayoutForImage()  // Only if switching from video
                        photoImageView.isHidden = false  // Ensure image is visible
                    }
                    // If no video player, image is already showing - don't touch it
                }
            }
            
            // 4. Clear faces (no visual jump). Do not hide name section here — wait until face detection
            // completes so we don't blink when moving from a photo with faces to another with faces.
            detectedFaces = []
            faceAssignments = []
            facesCollectionView.reloadData()
        }
        
        // 5. Update cache window for next scroll (can be async)
        startCachingDisplayImages(around: centeredIndex)
        // 6. Slide window toward older/newer if user scrolled near end/start (bounded memory, no limit on how far back)
        slideWindowForwardIfNeeded(centerIndex: centeredIndex)
        slideWindowBackwardIfNeeded(centerIndex: centeredIndex)
        
        // 6. Clean up queue
        cleanupQueueBehindCurrentPosition()
        
        // 7. Run face detection for the index that just became centered (pass index to avoid stale lookup)
        runFaceDetectionForCenteredPhoto(centeredIndex: centeredIndex)
        
        // 8. Auto-play video if needed
        if isValidCarouselIndex(centeredIndex),
           prioritizedAssets[centeredIndex].mediaType == .video,
           let player = videoPlayer {
            player.play()
            updatePlayPauseButton(isPlaying: true)
        }
    }
    
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if scrollView == photoCarouselCollectionView {
            let findCentered = findCenteredItemIndex()
            print("[NF] scrollViewDidEndScrollingAnimation: currentIndex=\(currentCarouselIndex) findCentered=\(findCentered ?? -1)")
            isUserTappingCarousel = false
            isProgrammaticallyScrollingCarousel = false
            // Do not set currentCarouselIndex from findCenteredItemIndex() here — the caller who started
            // the animated scroll (jumpToPhotoAtIndex, loadNextPhotoWithFaces, refineToBestPhoto…) already
            // set the correct index; with 4700+ items findCenteredItemIndex() can be wrong and would overwrite
            // a restored position (e.g. 4749 → 4771).
            carouselSelectionVisible = true
            UIView.performWithoutAnimation {
                photoCarouselCollectionView.reloadItems(at: photoCarouselCollectionView.indexPathsForVisibleItems)
            }
        }
    }
    
    private func runFaceDetectionForCenteredPhoto(centeredIndex: Int) {
        guard isValidCarouselIndex(centeredIndex) else { return }
        loadPhotoAtCarouselIndex(centeredIndex)
    }
    
    /// Index of the carousel item whose center is closest to the visible center (matches targetContentOffset snap; avoids off-by-one when center point falls on a boundary).
    /// Result is always a valid carousel index (clamped to 0..<carouselItemCount) or nil when the carousel is empty.
    private func findCenteredItemIndex() -> Int? {
        guard carouselItemCount > 0 else { return nil }
        let cv = photoCarouselCollectionView
        let centerX = cv.contentOffset.x + cv.bounds.width / 2
        let visibleRect = CGRect(origin: cv.contentOffset, size: cv.bounds.size)
        let raw: Int?
        if let attributes = cv.collectionViewLayout.layoutAttributesForElements(in: visibleRect), !attributes.isEmpty {
            raw = attributes.min(by: { abs($0.center.x - centerX) < abs($1.center.x - centerX) })?.indexPath.item
        } else {
            raw = cv.indexPathForItem(at: CGPoint(x: centerX, y: cv.bounds.height / 2))?.item
        }
        guard let item = raw else { return nil }
        return clampCarouselIndex(item)
    }
    
    private func loadPhotoAtCarouselIndex(_ index: Int) {
        guard isValidCarouselIndex(index) else { return }
        print("[NF] loadPhotoAtCarouselIndex: index=\(index) currentCarouselIndex=\(currentCarouselIndex)")
        saveCurrentPhotoAssignmentsToMemory()
        mainImageLoadTask?.cancel()
        mainImageLoadTask = Task {
            let asset = prioritizedAssets[index]
            
            // Handle videos - show frame first for smooth launch, then set up player after a brief delay
            if asset.mediaType == .video {
                guard let image = await loadOptimizedImage(for: asset) else {
                    await MainActor.run { self.mainImageLoadTask = nil }
                    return
                }
                let date = asset.creationDate ?? Date()
                await MainActor.run {
                    self.applyMainImage(image, date: date, asset: asset, forCarouselIndex: index)
                    self.detectedFaces = []
                    self.faceAssignments = []
                    self.facesCollectionView.reloadData()
                    self.updateFacesVisibility()
                }
                // Defer video player setup so first frame paints smoothly (avoids FIGSANDBOX jank on launch)
                try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
                let stillShowing = await MainActor.run { self.currentCarouselIndex == index }
                guard stillShowing else {
                    await MainActor.run { self.mainImageLoadTask = nil }
                    return
                }
                await self.setupVideoPlayer(for: asset, carouselIndex: index)
                await MainActor.run {
                    guard self.currentCarouselIndex == index else { return }
                    if self.shouldDeferPreprocessUntilFirstPhotoShown, !self.didStartDeferredPreprocess {
                        self.didStartDeferredPreprocess = true
                        self.deferPreprocessNextBatch()
                    }
                    self.mainImageLoadTask = nil
                }
                return
            }
            
            let date = asset.creationDate ?? Date()
            let cachedImage = await MainActor.run { self.cachedDisplayImages[index] }
            let thumbnailPlaceholder = await MainActor.run {
                self.isValidCarouselIndex(index) ? self.carouselThumbnails[index] : nil
            }
            var imageForDetection: UIImage?
            if let cached = cachedImage {
                imageForDetection = cached
                await MainActor.run {
                    self.applyMainImage(cached, date: date, asset: asset, forCarouselIndex: index)
                }
            } else {
                if let thumb = thumbnailPlaceholder {
                    await MainActor.run {
                        self.applyMainImage(thumb, date: date, asset: asset, forCarouselIndex: index)
                    }
                }
                let onFirst: (UIImage) -> Void = { [weak self] img in
                    guard let self = self else { return }
                    self.applyMainImage(img, date: date, asset: asset, forCarouselIndex: index)
                }
                guard let loadedImage = await loadOptimizedImage(for: asset, onFirstDelivery: onFirst) else {
                    await MainActor.run { self.mainImageLoadTask = nil }
                    return
                }
                imageForDetection = loadedImage
                await MainActor.run {
                    self.applyMainImage(loadedImage, date: date, asset: asset, forCarouselIndex: index)
                }
            }
            guard let image = imageForDetection else {
                await MainActor.run { self.mainImageLoadTask = nil }
                return
            }
            let (_, _) = await detectAndCheckFaceDiversity(image)
            await MainActor.run {
                guard self.currentCarouselIndex == index else { return }
                self.restoreAssignmentsFromMemory(assetIdentifier: asset.localIdentifier)
                self.facesCollectionView.reloadData()
                self.updateFacesVisibility()
                if !self.detectedFaces.isEmpty {
                    self.currentFaceIndex = 0
                    self.facesCollectionView.selectItem(
                        at: IndexPath(item: 0, section: 0),
                        animated: false,
                        scrollPosition: .centeredHorizontally
                    )
                }
                if self.shouldDeferPreprocessUntilFirstPhotoShown, !self.didStartDeferredPreprocess {
                    self.didStartDeferredPreprocess = true
                    self.deferPreprocessNextBatch()
                }
                self.mainImageLoadTask = nil
            }
        }
    }
}

extension WelcomeFaceNamingViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView == facesCollectionView {
            // Smaller faces for overlay style
            return CGSize(width: 50, height: 50)
        } else if collectionView == photoCarouselCollectionView, 
                  let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout {
            // Return the layout's calculated itemSize (which adapts to width)
            let size = flowLayout.itemSize
            // Safety check to prevent negative sizes
            return CGSize(width: max(44, size.width), height: max(44, size.height))
        }
        return CGSize(width: 44, height: 44) // Fallback
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView == photoCarouselCollectionView {
            return 2
        }
        return 8
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView == photoCarouselCollectionView {
            return 2
        }
        return 8
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        if collectionView == photoCarouselCollectionView,
           let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout {
            return flowLayout.sectionInset
        }
        return UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    }
}

extension WelcomeFaceNamingViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        var name: String
        // If suggestions are visible, Return = "accept first suggestion" and link to that existing contact
        if !suggestedContacts.isEmpty, let first = suggestedContacts.first {
            name = first.name ?? "Unnamed"
            faceAssignedExistingContact[currentFaceIndex] = first
            suggestedContacts = []
            nameSuggestionsTableView.reloadData()
            nameSuggestionsTableView.isHidden = true
            nameSuggestionsTableHeightConstraint?.constant = 0
            nameTextField.text = name
        } else {
            name = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        
        if currentFaceIndex < faceAssignments.count {
            faceAssignments[currentFaceIndex] = name
            
            // Reload the cell to show updated state
            let indexPath = IndexPath(item: currentFaceIndex, section: 0)
            facesCollectionView.reloadItems(at: [indexPath])
            
            // Move to next face if available
            if !name.isEmpty && currentFaceIndex < detectedFaces.count - 1 {
                currentFaceIndex += 1
                let nextIndexPath = IndexPath(item: currentFaceIndex, section: 0)
                
                // Select and scroll to next face
                facesCollectionView.selectItem(at: nextIndexPath, animated: true, scrollPosition: .centeredHorizontally)
                
                // Update text field with next face's name (if any)
                nameTextField.text = faceAssignments[currentFaceIndex]
                filterContactsForNameSuggestions()
                
                print("👤 Moved to next face: \(currentFaceIndex + 1) of \(detectedFaces.count)")
                
                // Keep keyboard open for next name
                return false
            }
            
        }
        
        // Dismiss the keyboard
        textField.resignFirstResponder()
        
        return false
    }
    
    func textFieldDidChangeSelection(_ textField: UITextField) {
        // Auto-save as user types for the currently selected face
        let name = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if currentFaceIndex < faceAssignments.count {
            faceAssignments[currentFaceIndex] = name
        }
        filterContactsForNameSuggestions()
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        // Defer to next run loop so keyboard animation isn't blocked by filter/reload
        DispatchQueue.main.async { [weak self] in
            self?.filterContactsForNameSuggestions()
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        suggestedContacts = []
        nameSuggestionsTableView.reloadData()
        nameSuggestionsTableView.isHidden = true
        nameSuggestionsTableHeightConstraint?.constant = 0
    }
}

// MARK: - Name suggestions table (contact autocompletion)

extension WelcomeFaceNamingViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard tableView == nameSuggestionsTableView else { return 0 }
        return suggestedContacts.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard tableView == nameSuggestionsTableView,
              indexPath.row < suggestedContacts.count,
              let cell = tableView.dequeueReusableCell(withIdentifier: NameSuggestionCell.reuseId, for: indexPath) as? NameSuggestionCell else {
            return UITableViewCell()
        }
        let contact = suggestedContacts[indexPath.row]
        cell.configure(name: contact.name ?? "Unnamed", photoData: contact.photo)
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard tableView == nameSuggestionsTableView, indexPath.row < suggestedContacts.count else { return }
        let contact = suggestedContacts[indexPath.row]
        let name = contact.name ?? "Unnamed"
        nameTextField.text = name
        if currentFaceIndex < faceAssignments.count {
            faceAssignments[currentFaceIndex] = name
            faceAssignedExistingContact[currentFaceIndex] = contact
        }
        let rowPath = IndexPath(item: currentFaceIndex, section: 0)
        facesCollectionView.reloadItems(at: [rowPath])
        suggestedContacts = []
        nameSuggestionsTableView.reloadData()
        nameSuggestionsTableView.isHidden = true
        nameSuggestionsTableHeightConstraint?.constant = 0
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

private final class NameSuggestionCell: UITableViewCell {
    static let reuseId = "NameSuggestionCell"
    
    private let thumbnailView: UIImageView = {
        let v = UIImageView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.layer.cornerRadius = 16
        v.layer.cornerCurve = .continuous
        v.backgroundColor = .tertiarySystemBackground
        return v
    }()
    
    private let nameLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 17, weight: .regular)
        l.textColor = .label
        return l
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(thumbnailView)
        contentView.addSubview(nameLabel)
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 32),
            thumbnailView.heightAnchor.constraint(equalToConstant: 32),
            nameLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
        ])
        backgroundColor = .secondarySystemGroupedBackground
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(name: String, photoData: Data) {
        nameLabel.text = name
        if !photoData.isEmpty, let image = UIImage(data: photoData) {
            thumbnailView.image = image
            thumbnailView.isHidden = false
        } else {
            thumbnailView.image = nil
            thumbnailView.isHidden = false
            thumbnailView.backgroundColor = .tertiarySystemBackground
        }
    }
}

// MARK: - Prefetching

extension WelcomeFaceNamingViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard collectionView == photoCarouselCollectionView else { return }
        
        // Prefetch thumbnails for cells about to become visible
        for indexPath in indexPaths {
            guard isValidCarouselIndex(indexPath.item) else { continue }
            loadThumbnailAtIndex(indexPath.item)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        guard collectionView == photoCarouselCollectionView else { return }
        
        // Cancel loading for cells that scrolled out of view
        for indexPath in indexPaths {
            thumbnailLoadingTasks[indexPath.item]?.cancel()
            thumbnailLoadingTasks.removeValue(forKey: indexPath.item)
        }
    }
}

// MARK: - Photo Carousel Flow Layout

private final class PhotoCarouselFlowLayout: UICollectionViewFlowLayout {
    
    private var itemSpacing: CGFloat { 1.5 }
    /// Minimum edge padding when centering insets would be negative (e.g. single very wide item).
    private var minimumEdgeInset: CGFloat { 8 }
    
    override init() {
        super.init()
        setupLayout()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayout()
    }
    
    private func setupLayout() {
        scrollDirection = .horizontal
        minimumLineSpacing = itemSpacing
        minimumInteritemSpacing = itemSpacing
        // Section insets are set in prepare() so first/last items can be centered (Apple-style carousel).
        sectionInset = UIEdgeInsets(top: 2, left: minimumEdgeInset, bottom: 2, right: minimumEdgeInset)
    }
    
    override func prepare() {
        super.prepare()
        
        guard let collectionView = collectionView else { return }
        
        let bounds = collectionView.bounds
        // Calculate item size dynamically - portrait oriented (taller than wide)
        let height = bounds.height - 4 // Account for top/bottom insets
        
        // Safety check: ensure height is valid before calculating
        guard height > 0 else {
            itemSize = CGSize(width: 44, height: 66) // Fallback portrait size
            sectionInset = UIEdgeInsets(top: 2, left: minimumEdgeInset, bottom: 2, right: minimumEdgeInset)
            return
        }
        
        // Portrait aspect ratio: width is 2/3 of height (or even narrower for more vertical look)
        let itemHeight = max(66, height)
        let itemWidth = max(40, floor(itemHeight * 0.6)) // 60% width-to-height ratio for strong portrait
        
        itemSize = CGSize(width: itemWidth, height: itemHeight)
        
        // Centering insets: so the first item and last item can be scrolled to the visual center.
        // Leading/trailing = (visible width - item width) / 2 (capped so we never use negative insets).
        let horizontalInset = max(minimumEdgeInset, (bounds.width - itemWidth) / 2)
        sectionInset = UIEdgeInsets(top: 2, left: horizontalInset, bottom: 2, right: horizontalInset)
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let cv = collectionView else { return false }
        return newBounds.size != cv.bounds.size
    }
    
    // MARK: - Snap to Center (Apple Photos behavior)
    
    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        guard let collectionView = collectionView else {
            return proposedContentOffset
        }
        
        let targetRect = CGRect(
            x: proposedContentOffset.x,
            y: 0,
            width: collectionView.bounds.width,
            height: collectionView.bounds.height
        )
        
        guard let layoutAttributes = super.layoutAttributesForElements(in: targetRect) else {
            return proposedContentOffset
        }
        
        let centerX = proposedContentOffset.x + collectionView.bounds.width / 2
        
        var closestAttribute: UICollectionViewLayoutAttributes?
        var minimumDistance = CGFloat.greatestFiniteMagnitude
        
        // Find the item closest to the center
        for attributes in layoutAttributes {
            let distance = abs(attributes.center.x - centerX)
            if distance < minimumDistance {
                minimumDistance = distance
                closestAttribute = attributes
            }
        }
        
        guard let closest = closestAttribute else {
            return proposedContentOffset
        }
        
        // Calculate offset to center the closest item
        let targetX = closest.center.x - collectionView.bounds.width / 2
        
        // Clamp to valid content offset range
        let maxOffsetX = collectionView.contentSize.width - collectionView.bounds.width
        let clampedX = max(0, min(targetX, maxOffsetX))
        
        return CGPoint(x: clampedX, y: proposedContentOffset.y)
    }
}

// MARK: - Face Cell

private final class FaceCell: UICollectionViewCell {
    static let reuseIdentifier = "FaceCell"
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 25
        imageView.layer.borderWidth = 2.5
        imageView.layer.borderColor = UIColor.white.cgColor
        imageView.isUserInteractionEnabled = false  // Let touches pass through to cell
        return imageView
    }()
    
    private let statusIndicator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemGreen
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.white.cgColor
        view.isUserInteractionEnabled = false  // Let touches pass through to cell
        view.isHidden = true
        return view
    }()
    
    private let checkmarkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        let config = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        imageView.image = UIImage(systemName: "checkmark", withConfiguration: config)
        return imageView
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
        statusIndicator.addSubview(checkmarkImageView)
        
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 50),
            imageView.heightAnchor.constraint(equalToConstant: 50),
            
            statusIndicator.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 2),
            statusIndicator.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            statusIndicator.widthAnchor.constraint(equalToConstant: 16),
            statusIndicator.heightAnchor.constraint(equalToConstant: 16),
            
            checkmarkImageView.centerXAnchor.constraint(equalTo: statusIndicator.centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: statusIndicator.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 9),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 9),
        ])
    }
    
    func configure(with image: UIImage, name: String, isNamed: Bool) {
        imageView.image = image
        
        if isNamed {
            statusIndicator.isHidden = false
        } else {
            statusIndicator.isHidden = true
        }
    }
    
    override var isSelected: Bool {
        didSet {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                if self.isSelected {
                    self.imageView.layer.borderColor = UIColor.systemBlue.cgColor
                    self.imageView.layer.borderWidth = 3.5
                    self.imageView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
                } else {
                    self.imageView.layer.borderColor = UIColor.white.cgColor
                    self.imageView.layer.borderWidth = 2.5
                    self.imageView.transform = .identity
                }
            }
        }
    }
    
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.imageView.alpha = self.isHighlighted ? 0.7 : 1.0
            }
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.transform = .identity
        imageView.alpha = 1.0
    }
}

private final class PhotoCarouselCell: UICollectionViewCell {
    static let reuseIdentifier = "PhotoCarouselCell"
    
    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()
    
    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 4
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = UIColor.quaternarySystemFill
        
        // Apple Photos-style subtle border
        imageView.layer.borderWidth = 0.5
        imageView.layer.borderColor = UIColor.separator.withAlphaComponent(0.3).cgColor
        
        return imageView
    }()
    
    private let selectionRing: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 4
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 2.5
        view.layer.borderColor = UIColor.systemBlue.cgColor
        view.isHidden = true
        view.backgroundColor = .clear
        return view
    }()
    
    private let videoIndicator: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.isHidden = true
        
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        imageView.image = UIImage(systemName: "play.fill", withConfiguration: config)
        
        // Add subtle shadow for visibility
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOffset = CGSize(width: 0, height: 1)
        imageView.layer.shadowOpacity = 0.5
        imageView.layer.shadowRadius = 2
        
        return imageView
    }()
    
    private let placeholderView: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = .tertiaryLabel
        return indicator
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.addSubview(containerView)
        containerView.addSubview(imageView)
        containerView.addSubview(selectionRing)
        containerView.addSubview(videoIndicator)
        containerView.addSubview(placeholderView)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            selectionRing.topAnchor.constraint(equalTo: containerView.topAnchor),
            selectionRing.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            selectionRing.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            selectionRing.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            videoIndicator.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -3),
            videoIndicator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -3),
            videoIndicator.widthAnchor.constraint(equalToConstant: 12),
            videoIndicator.heightAnchor.constraint(equalToConstant: 12),
            
            placeholderView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
        ])
    }
    
    func configure(with image: UIImage?, isCurrentPhoto: Bool, isVideo: Bool = false) {
        if let image = image {
            imageView.image = image
            imageView.tintColor = nil
            imageView.alpha = 1.0
            placeholderView.stopAnimating()
        } else {
            imageView.image = nil
            imageView.alpha = 1.0
            placeholderView.startAnimating()
        }
        
        videoIndicator.isHidden = !isVideo
        
        // Blue border: show only when carousel has stopped; hide immediately when scroll starts (no animation).
        selectionRing.isHidden = !isCurrentPhoto
        
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            if isCurrentPhoto {
                self.containerView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
                self.imageView.alpha = 1.0
            } else {
                self.containerView.transform = .identity
                if image != nil {
                    self.imageView.alpha = 0.65
                }
            }
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        selectionRing.isHidden = true
        videoIndicator.isHidden = true
        containerView.transform = .identity
        placeholderView.stopAnimating()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension WelcomeFaceNamingViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't handle tap gesture if touch is on faces collection view or any interactive control
        if touch.view is UIControl {
            return false
        }
        
        // Check if touch is within faces collection view bounds
        let locationInFacesView = touch.location(in: facesCollectionView)
        if facesCollectionView.bounds.contains(locationInFacesView) {
            print("🚫 Tap gesture ignoring touch on faces collection view")
            return false
        }
        
        // Check if touch is within photo carousel bounds
        let locationInCarousel = touch.location(in: photoCarouselCollectionView)
        if photoCarouselCollectionView.bounds.contains(locationInCarousel) {
            return false
        }
        
        return true
    }
}

// MARK: - Array Safe Subscript Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
