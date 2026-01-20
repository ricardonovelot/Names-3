import UIKit
import Photos
import SwiftData

/// Production-grade paginated photo viewer following Apple Photos.app patterns
/// - Uses UIPageViewController for efficient memory management
/// - Maintains grid scroll position across transitions
/// - Prefetches adjacent photos for smooth scrolling
/// - Integrates PhotoDetailViewController for face detection per photo
final class PhotoPagerViewController: UIViewController {
    
    // MARK: - Properties
    
    private let assets: [PHAsset]
    private let startingIndex: Int
    private let imageManager: PHCachingImageManager
    private let contactsContext: ModelContext
    private let onDismiss: () -> Void
    
    private var pageViewController: UIPageViewController!
    private var currentIndex: Int
    private let pageControl = UIPageControl()
    
    // Cache for loaded images to avoid redundant fetches
    private var imageCache: [Int: UIImage] = [:]
    private let prefetchRange = 2 // Number of photos to prefetch on each side
    
    // Face detection view models per photo
    private var faceViewModels: [Int: FaceDetectionViewModel] = [:]
    
    // MARK: - Initialization
    
    init(
        assets: [PHAsset],
        startingIndex: Int,
        imageManager: PHCachingImageManager,
        contactsContext: ModelContext,
        onDismiss: @escaping () -> Void
    ) {
        self.assets = assets
        self.startingIndex = startingIndex
        self.currentIndex = startingIndex
        self.imageManager = imageManager
        self.contactsContext = contactsContext
        self.onDismiss = onDismiss
        
        super.init(nibName: nil, bundle: nil)
        
        print("📖 [PhotoPager] Initialized with \(assets.count) assets, starting at index \(startingIndex)")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupPageViewController()
        setupPageControl()
        setupNavigationBar()
        
        // Load initial photo
        loadPhotoDetailViewController(at: startingIndex, animated: false)
        
        // Start prefetching adjacent photos
        prefetchAdjacentPhotos(around: startingIndex)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Clear cache to free memory
        imageCache.removeAll()
        faceViewModels.removeAll()
        imageManager.stopCachingImagesForAllAssets()
    }
    
    // MARK: - Setup
    
    private func setupPageViewController() {
        pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )
        
        pageViewController.dataSource = self
        pageViewController.delegate = self
        
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        pageViewController.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        view.backgroundColor = .systemBackground
    }
    
    private func setupPageControl() {
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = assets.count
        pageControl.currentPage = startingIndex
        pageControl.isUserInteractionEnabled = false
        pageControl.hidesForSinglePage = true
        
        // Apple's pattern: Only show page control for smaller sets
        pageControl.alpha = assets.count <= 20 ? 1.0 : 0.0
        
        view.addSubview(pageControl)
        
        NSLayoutConstraint.activate([
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(dismissTapped)
        )
        
        updateNavigationTitle()
    }
    
    // MARK: - Photo Loading
    
    private func loadPhotoDetailViewController(at index: Int, animated: Bool) {
        guard index >= 0 && index < assets.count else {
            print("⚠️ [PhotoPager] Index \(index) out of bounds")
            return
        }
        
        let asset = assets[index]
        
        // Check cache first
        if let cachedImage = imageCache[index] {
            print("✅ [PhotoPager] Using cached image for index \(index)")
            presentDetailViewController(
                with: cachedImage,
                date: asset.creationDate,
                at: index,
                animated: animated
            )
            return
        }
        
        // Load from Photos framework
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .exact
        
        // Apple's pattern: Use screen-appropriate size for paging
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * UIScreen.main.scale,
            height: UIScreen.main.bounds.height * UIScreen.main.scale
        )
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            guard let self = self else { return }
            
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            
            guard !isDegraded, !isCancelled, let image = image else {
                print("⚠️ [PhotoPager] Failed to load image at index \(index)")
                return
            }
            
            // Cache the loaded image
            self.imageCache[index] = image
            
            Task { @MainActor in
                self.presentDetailViewController(
                    with: image,
                    date: asset.creationDate,
                    at: index,
                    animated: animated
                )
            }
        }
    }
    
    private func presentDetailViewController(
        with image: UIImage,
        date: Date?,
        at index: Int,
        animated: Bool
    ) {
        // Get or create face detection view model for this photo
        let viewModel: FaceDetectionViewModel
        if let existing = faceViewModels[index] {
            viewModel = existing
        } else {
            viewModel = FaceDetectionViewModel()
            faceViewModels[index] = viewModel
        }
        
        let detailVC = PhotoDetailViewController(
            image: image,
            date: date,
            contactsContext: contactsContext,
            faceDetectionViewModel: viewModel
        )
        
        // Override back action to handle paging context
        detailVC.customBackAction = { [weak self] in
            // Do nothing - we're in paging mode
            // User can swipe to navigate or tap X to dismiss entire pager
        }
        
        let direction: UIPageViewController.NavigationDirection = index > currentIndex ? .forward : .reverse
        
        pageViewController.setViewControllers(
            [detailVC],
            direction: direction,
            animated: animated,
            completion: { [weak self] _ in
                self?.currentIndex = index
                self?.pageControl.currentPage = index
                self?.updateNavigationTitle()
                
                // Prefetch adjacent photos for smooth scrolling
                self?.prefetchAdjacentPhotos(around: index)
            }
        )
    }
    
    // MARK: - Prefetching (Apple's Photos.app pattern)
    
    private func prefetchAdjacentPhotos(around centerIndex: Int) {
        let startIndex = max(0, centerIndex - prefetchRange)
        let endIndex = min(assets.count - 1, centerIndex + prefetchRange)
        
        for index in startIndex...endIndex {
            // Skip if already cached or is the current photo
            if imageCache[index] != nil || index == centerIndex {
                continue
            }
            
            let asset = assets[index]
            
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            let targetSize = CGSize(
                width: UIScreen.main.bounds.width * UIScreen.main.scale,
                height: UIScreen.main.bounds.height * UIScreen.main.scale
            )
            
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, info in
                guard let self = self else { return }
                
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                
                if !isDegraded, !isCancelled, let image = image {
                    self.imageCache[index] = image
                    print("✅ [PhotoPager] Prefetched image at index \(index)")
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func dismissTapped() {
        onDismiss()
        dismiss(animated: true)
    }
    
    private func updateNavigationTitle() {
        // Apple's pattern: Show "X of Y" for context
        navigationItem.title = "\(currentIndex + 1) of \(assets.count)"
    }
}

// MARK: - UIPageViewControllerDataSource

extension PhotoPagerViewController: UIPageViewControllerDataSource {
    
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        let previousIndex = currentIndex - 1
        
        guard previousIndex >= 0 else {
            return nil
        }
        
        // Create a temporary VC to return
        // The actual loading will happen in didFinishAnimating
        let placeholderVC = UIViewController()
        placeholderVC.view.backgroundColor = .systemBackground
        
        return placeholderVC
    }
    
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        let nextIndex = currentIndex + 1
        
        guard nextIndex < assets.count else {
            return nil
        }
        
        // Create a temporary VC to return
        // The actual loading will happen in didFinishAnimating
        let placeholderVC = UIViewController()
        placeholderVC.view.backgroundColor = .systemBackground
        
        return placeholderVC
    }
}

// MARK: - UIPageViewControllerDelegate

extension PhotoPagerViewController: UIPageViewControllerDelegate {
    
    func pageViewController(
        _ pageViewController: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
    ) {
        // Apple's pattern: Start loading before animation completes
        print("📖 [PhotoPager] Will transition from index \(currentIndex)")
    }
    
    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed else { return }
        
        // Determine which direction the user swiped
        // Load the appropriate photo
        
        // Since we're using placeholders, we need to reload with actual content
        if let firstVC = pageViewController.viewControllers?.first,
           firstVC.children.isEmpty { // It's a placeholder
            
            // Determine the new index based on scroll direction
            // We'll check gesture recognizers for scroll direction
            var newIndex = currentIndex
            
            for recognizer in pageViewController.gestureRecognizers {
                if let panGesture = recognizer as? UIPanGestureRecognizer {
                    let velocity = panGesture.velocity(in: pageViewController.view)
                    
                    if velocity.x < 0 {
                        // Swiped left → next photo
                        newIndex = currentIndex + 1
                    } else if velocity.x > 0 {
                        // Swiped right → previous photo
                        newIndex = currentIndex - 1
                    }
                }
            }
            
            // Fallback: try both directions
            if newIndex == currentIndex {
                // Check if next or previous index has cached image
                if imageCache[currentIndex + 1] != nil && currentIndex + 1 < assets.count {
                    newIndex = currentIndex + 1
                } else if imageCache[currentIndex - 1] != nil && currentIndex - 1 >= 0 {
                    newIndex = currentIndex - 1
                }
            }
            
            guard newIndex != currentIndex else { return }
            
            loadPhotoDetailViewController(at: newIndex, animated: false)
        }
    }
}