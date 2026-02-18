import UIKit
import Photos
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names", category: "PhotosGrid")

// MARK: - Photos Grid View Controller

final class PhotosGridViewController: UIViewController {
    
    // MARK: - Types
    
    typealias PhotoPickedHandler = (UIImage, Date?) -> Void
    
    private enum Section: Hashable {
        case group(String)
    }
    
    private struct Item: Hashable {
        let assetID: String
        let asset: PHAsset
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(assetID)
        }
        
        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.assetID == rhs.assetID
        }
    }
    
    private enum LoadState {
        case idle
        case loading
        case loaded
        case error(String)
    }
    
    // MARK: - Properties
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    private var loadingView: LoadingStateView!
    
    private let imageManager = PHCachingImageManager()
    private let cache = ImageCacheService.shared
    private let grouper = PhotoGroupingService()
    
    private var photoGroups: [PhotoGroup] = []
    private var itemsBySection: [Section: [Item]] = [:]
    
    private let itemSize: CGFloat = 160
    private let itemSpacing: CGFloat = 12
    private let sectionInset = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 24, trailing: 16)
    
    private var thumbnailSize: CGSize = .zero
    private let scale = UIScreen.main.scale
    
    private var loadTask: Task<Void, Never>?
    private var expandTask: Task<Void, Never>?
    private var changeObserver: PHPhotoLibraryChangeObserver?
    private var isInitialLoad = true
    private var hasScrolledToBottom = false
    private var loadState: LoadState = .idle

    /// Cap on total assets loaded in the grid so Phase 2 doesn't load entire library (can be 50k+).
    private static let maxTotalAssetsInGrid = 5000

    var onPhotoPicked: PhotoPickedHandler?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("PhotosGridViewController viewDidLoad")
        print("🎬 PhotosGridViewController viewDidLoad")
        NSLog("🎬 PhotosGridViewController viewDidLoad")
        
        view.backgroundColor = .systemGroupedBackground
        
        computeThumbnailSize()
        setupLoadingView()
        setupCollectionView()
        setupDataSource()
        registerForPhotoLibraryChanges()
        
        // Show loading state immediately
        setLoadState(.loading)
        
        ProcessReportCoordinator.shared.register(name: "PhotosGridViewController") { [weak self] in
            guard let self else {
                return ProcessReportSnapshot(name: "PhotosGridViewController", payload: ["state": "released"])
            }
            return ProcessReportSnapshot(
                name: "PhotosGridViewController",
                payload: [
                    "photoGroupsCount": "\(self.photoGroups.count)",
                    "loadState": "\(self.loadState)",
                    "thumbnailW": "\(Int(self.thumbnailSize.width))"
                ]
            )
        }
        
        loadPhotos()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("🎬 viewDidAppear")
        NSLog("🎬 viewDidAppear")
    }
    
    deinit {
        ProcessReportCoordinator.shared.unregister(name: "PhotosGridViewController")
        logger.info("PhotosGridViewController deinit")
        print("🎬 PhotosGridViewController deinit")
        if let observer = changeObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(observer)
        }
        loadTask?.cancel()
        expandTask?.cancel()
    }
    
    // MARK: - Setup
    
    private func computeThumbnailSize() {
        let dimension = floor(itemSize * scale)
        thumbnailSize = CGSize(width: dimension, height: dimension)
        logger.debug("Computed thumbnail size: \(dimension)x\(dimension) @\(self.scale)x")
        print("📐 Thumbnail size: \(dimension)x\(dimension) @\(scale)x")
        NSLog("📐 Thumbnail size: %.0fx%.0f @%.0fx", dimension, dimension, scale)
    }
    
    private func setupLoadingView() {
        loadingView = LoadingStateView()
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingView)
        
        NSLayoutConstraint.activate([
            loadingView.topAnchor.constraint(equalTo: view.topAnchor),
            loadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        loadingView.isHidden = true
        print("✅ Loading view configured")
    }
    
    private func setupCollectionView() {
        let layout = createCompositionalLayout()
        
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.register(PhotoGridCell.self, forCellWithReuseIdentifier: PhotoGridCell.reuseIdentifier)
        collectionView.register(
            PhotoGroupHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: PhotoGroupHeaderView.reuseIdentifier
        )
        
        view.insertSubview(collectionView, belowSubview: loadingView)
        logger.info("UICollectionView configured with compositional layout")
        print("✅ UICollectionView configured")
        NSLog("✅ UICollectionView configured")
    }
    
    private func createCompositionalLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, environment in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .absolute(self.itemSize),
                heightDimension: .absolute(self.itemSize)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .absolute(self.itemSize),
                heightDimension: .absolute(self.itemSize)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            
            let section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous
            section.interGroupSpacing = self.itemSpacing
            section.contentInsets = self.sectionInset
            
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .estimated(60)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            
            return section
        }
        
        print("📐 Compositional layout created")
        return layout
    }
    
    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, item in
            guard let self else { return UICollectionViewCell() }
            
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: PhotoGridCell.reuseIdentifier,
                for: indexPath
            ) as! PhotoGridCell
            
            cell.configure(with: item.asset, targetSize: self.thumbnailSize, cache: self.cache, imageManager: self.imageManager)
            return cell
        }
        
        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard let self else { return nil }
            guard kind == UICollectionView.elementKindSectionHeader else { return nil }
            
            guard indexPath.section < self.photoGroups.count else {
                print("⚠️ Header requested for section \(indexPath.section) but only \(self.photoGroups.count) groups exist")
                return nil
            }
            
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: PhotoGroupHeaderView.reuseIdentifier,
                for: indexPath
            ) as! PhotoGroupHeaderView
            
            let group = self.photoGroups[indexPath.section]
            header.configure(title: group.title, subtitle: group.subtitle)
            return header
        }
        
        logger.info("UICollectionViewDiffableDataSource configured")
        print("✅ DataSource configured")
        NSLog("✅ DataSource configured")
    }
    
    private func registerForPhotoLibraryChanges() {
        changeObserver = PhotoLibraryService.shared.observeChanges { [weak self] in
            guard let self else { return }
            logger.info("PHPhotoLibrary change detected, reloading")
            print("📸 Photo library changed, reloading")
            Task { @MainActor in
                self.loadPhotos()
            }
        }
    }
    
    // MARK: - State Management
    
    private func setLoadState(_ state: LoadState) {
        loadState = state
        
        switch state {
        case .idle:
            loadingView.isHidden = true
            collectionView.isHidden = true
            
        case .loading:
            loadingView.isHidden = false
            loadingView.showLoading(message: "Loading photos...")
            collectionView.isHidden = true
            print("⏳ Showing loading state")
            NSLog("⏳ Loading state visible")
            
        case .loaded:
            loadingView.isHidden = true
            collectionView.isHidden = false
            print("✅ Showing content")
            NSLog("✅ Content visible")
            
        case .error(let message):
            loadingView.isHidden = false
            loadingView.showError(message: message)
            collectionView.isHidden = true
            print("❌ Error state: \(message)")
        }
    }
    
    // MARK: - Loading
    
    private func loadPhotos() {
        loadTask?.cancel()
        expandTask?.cancel()
        
        logger.info("loadPhotos() started")
        print("🔄 loadPhotos() started")
        NSLog("🔄 loadPhotos() started")
        
        setLoadState(.loading)
        
        loadTask = Task { [weak self] in
            guard let self else { return }
            
            let overallStart = CFAbsoluteTimeGetCurrent()
            
            let status = await PhotoLibraryService.shared.requestAuthorization()
            guard status == .authorized || status == .limited else {
                logger.error("Photo library authorization denied: \(String(describing: status))")
                print("❌ Authorization denied: \(status)")
                NSLog("❌ Authorization denied: %@", String(describing: status))
                await MainActor.run {
                    self.setLoadState(.error("Photos access is required"))
                }
                return
            }
            logger.info("Photo library authorized: \(String(describing: status))")
            print("✅ Authorization: \(status)")
            NSLog("✅ Authorization: %@", String(describing: status))
            
            // PHASE 1: Quick initial load with recent photos only
            let initialStart = CFAbsoluteTimeGetCurrent()
            let initialLimit = 300
            print("⚡️ Phase 1: Loading \(initialLimit) most recent photos")
            NSLog("⚡️ Phase 1: %d photos", initialLimit)
            
            let initialAssets = self.fetchAssets(excludingScreenshots: true, fetchLimit: initialLimit)
            let initialFetchDuration = CFAbsoluteTimeGetCurrent() - initialStart
            print("📥 Phase 1 fetch: \(initialAssets.count) assets in \(String(format: "%.3f", initialFetchDuration))s")
            NSLog("📥 Phase 1: %d assets in %.3fs", initialAssets.count, initialFetchDuration)
            
            guard !initialAssets.isEmpty else {
                logger.warning("No assets found")
                print("⚠️ No assets found")
                NSLog("⚠️ No assets")
                await MainActor.run {
                    self.setLoadState(.error("No photos found"))
                }
                return
            }
            
            let groupStart = CFAbsoluteTimeGetCurrent()
            let initialGroups = await self.grouper.groupAssets(initialAssets)
            let groupDuration = CFAbsoluteTimeGetCurrent() - groupStart
            print("📊 Phase 1 grouping: \(initialGroups.count) groups in \(String(format: "%.3f", groupDuration))s")
            NSLog("📊 Phase 1: %d groups in %.3fs", initialGroups.count, groupDuration)
            
            if Task.isCancelled {
                print("⚠️ Load cancelled")
                return
            }
            
            let phase1Duration = CFAbsoluteTimeGetCurrent() - overallStart
            print("⏱ Phase 1 total: \(String(format: "%.3f", phase1Duration))s")
            NSLog("⏱ Phase 1: %.3fs", phase1Duration)
            
            // Show initial content immediately
            await MainActor.run {
                self.photoGroups = []
                self.applySnapshot(groups: initialGroups, isInitial: true)
                self.setLoadState(.loaded)
                print("✅ Initial content visible after \(String(format: "%.3f", phase1Duration))s")
                NSLog("✅ Visible: %.3fs", phase1Duration)
            }
            
            self.preheatInitialAssets(from: initialGroups)
            
            // PHASE 2: Load remaining photos in background (capped to avoid very long waits on large libraries)
            self.loadRemainingPhotos(alreadyLoaded: initialAssets.count, initialLimit: initialLimit, maxTotal: Self.maxTotalAssetsInGrid)
        }
    }
    
    private func loadRemainingPhotos(alreadyLoaded: Int, initialLimit: Int, maxTotal: Int = 5000) {
        expandTask = Task { [weak self] in
            guard let self else { return }
            
            print("🔄 Phase 2: Loading up to \(maxTotal) photos in background")
            NSLog("🔄 Phase 2 started (max %d)", maxTotal)
            
            // Small delay to let UI settle
            try? await Task.sleep(for: .milliseconds(300))
            
            if Task.isCancelled { return }
            
            let phase2Start = CFAbsoluteTimeGetCurrent()
            let allAssets = self.fetchAssets(excludingScreenshots: true, fetchLimit: maxTotal)
            let newAssetCount = allAssets.count - alreadyLoaded
            
            guard newAssetCount > 0 else {
                print("✅ No additional photos to load")
                NSLog("✅ Phase 2: no new photos")
                return
            }
            
            print("📥 Phase 2: \(newAssetCount) additional photos found")
            NSLog("📥 Phase 2: %d new", newAssetCount)
            
            let allGroups = await self.grouper.groupAssets(allAssets)
            
            if Task.isCancelled {
                print("⚠️ Phase 2 cancelled")
                return
            }
            
            let phase2Duration = CFAbsoluteTimeGetCurrent() - phase2Start
            print("📊 Phase 2: \(allGroups.count) total groups in \(String(format: "%.3f", phase2Duration))s")
            NSLog("📊 Phase 2: %d groups, %.3fs", allGroups.count, phase2Duration)
            
            await MainActor.run {
                self.applySnapshot(groups: allGroups, isInitial: false)
                print("✅ Full library loaded")
                NSLog("✅ Phase 2 complete")
            }
            
            self.preheatInitialAssets(from: allGroups)
        }
    }
    
    private func fetchAssets(excludingScreenshots: Bool, fetchLimit: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if fetchLimit > 0 {
            options.fetchLimit = fetchLimit
        }
        
        if excludingScreenshots {
            let screenshotBit = PHAssetMediaSubtype.photoScreenshot.rawValue
            options.predicate = NSPredicate(
                format: "mediaType == %d AND (NOT ((mediaSubtypes & %d) != 0))",
                PHAssetMediaType.image.rawValue,
                screenshotBit
            )
        } else {
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        }
        
        let fetchResult = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        return assets
    }
    
    private func applySnapshot(groups: [PhotoGroup], isInitial: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        itemsBySection.removeAll()
        
        print("📸 Building snapshot: \(groups.count) groups")
        NSLog("📸 Snapshot: %d groups", groups.count)
        
        let reversedGroups = groups.reversed()
        
        for (index, group) in reversedGroups.enumerated() {
            let section = Section.group(group.id)
            snapshot.appendSections([section])
            
            let items = group.representativeAssets.map { asset in
                Item(assetID: asset.localIdentifier, asset: asset)
            }
            snapshot.appendItems(items, toSection: section)
            itemsBySection[section] = items
            
            if index < 2 || index >= reversedGroups.count - 2 {
                print("  \(index): \(group.title) (\(items.count) items)")
            } else if index == 2 {
                print("  ... (\(reversedGroups.count - 4) more) ...")
            }
        }
        
        self.photoGroups = Array(reversedGroups)
        
        print("📊 Applying: \(snapshot.numberOfSections) sections, \(snapshot.numberOfItems) items")
        NSLog("📊 Apply: %d sections, %d items", snapshot.numberOfSections, snapshot.numberOfItems)
        
        let shouldScroll = isInitial && isInitialLoad && !hasScrolledToBottom
        
        dataSource.apply(snapshot, animatingDifferences: !isInitial) {
            if shouldScroll {
                self.scrollToBottom(animated: false)
                self.isInitialLoad = false
                self.hasScrolledToBottom = true
            }
            self.logContentSize()
        }
    }
    
    private func scrollToBottom(animated: Bool) {
        guard collectionView.numberOfSections > 0 else { return }
        
        let lastSection = collectionView.numberOfSections - 1
        let itemsInLastSection = collectionView.numberOfItems(inSection: lastSection)
        
        guard itemsInLastSection > 0 else { return }
        
        let lastIndexPath = IndexPath(item: itemsInLastSection - 1, section: lastSection)
        
        // Use performBatchUpdates to ensure layout is complete before scrolling (documented UIKit pattern)
        collectionView.performBatchUpdates(nil) { _ in
            self.collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: animated)
        }
    }
    
    private func logContentSize() {
        let contentSize = collectionView.contentSize
        let frameSize = collectionView.frame.size
        let sections = collectionView.numberOfSections
        var items = 0
        for s in 0..<sections {
            items += collectionView.numberOfItems(inSection: s)
        }
        
        print("📏 Content: \(Int(contentSize.height))pt, Frame: \(Int(frameSize.height))pt")
        print("📏 Sections: \(sections), Items: \(items)")
        NSLog("📏 %dx%d sections/items", sections, items)
    }
    
    private func preheatInitialAssets(from groups: [PhotoGroup]) {
        let assetsToHeat = groups.suffix(6).flatMap { $0.representativeAssets }.suffix(36)
        guard !assetsToHeat.isEmpty else { return }
        
        print("⚡️ Preheating \(assetsToHeat.count) assets")
        NSLog("⚡️ Preheat: %d", assetsToHeat.count)
        imageManager.startCachingImages(
            for: Array(assetsToHeat),
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: photoRequestOptions()
        )
    }
    
    private func photoRequestOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }
}

// MARK: - UICollectionViewDelegate

extension PhotosGridViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        print("👆 Tapped: s\(indexPath.section) i\(indexPath.item)")
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        let maxDimension: CGFloat = 2048
        let targetSize = CGSize(width: maxDimension, height: maxDimension)
        
        imageManager.requestImage(
            for: item.asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            if let image {
                DispatchQueue.main.async {
                    self?.onPhotoPicked?(image, item.asset.creationDate)
                }
            }
        }
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offset = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.frame.height
        let adjustedInset = scrollView.adjustedContentInset
        let maxOffset = contentHeight - frameHeight + adjustedInset.bottom
        
        if Int(offset) % 200 == 0 && maxOffset > 0 {
            let progress = Int((offset / maxOffset) * 100)
            print("📜 Offset: \(Int(offset)), \(progress)%")
        }
    }
}

// MARK: - UICollectionViewDataSourcePrefetching

extension PhotosGridViewController: UICollectionViewDataSourcePrefetching {
    private static let prefetchLimit = 24
    
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let assets = indexPaths.prefix(Self.prefetchLimit).compactMap { dataSource.itemIdentifier(for: $0)?.asset }
        guard !assets.isEmpty else { return }
        
        imageManager.startCachingImages(
            for: Array(assets),
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: photoRequestOptions()
        )
    }
    
    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let assets = indexPaths.compactMap { dataSource.itemIdentifier(for: $0)?.asset }
        guard !assets.isEmpty else { return }
        
        imageManager.stopCachingImages(
            for: assets,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: photoRequestOptions()
        )
    }
}

// MARK: - Loading State View

private final class LoadingStateView: UIView {
    private let containerStack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()
    private let errorLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        backgroundColor = .systemGroupedBackground
        
        containerStack.axis = .vertical
        containerStack.alignment = .center
        containerStack.spacing = 16
        containerStack.translatesAutoresizingMaskIntoConstraints = false
        
        messageLabel.font = .systemFont(ofSize: 17)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        
        errorLabel.font = .systemFont(ofSize: 17)
        errorLabel.textColor = .systemRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        
        containerStack.addArrangedSubview(spinner)
        containerStack.addArrangedSubview(messageLabel)
        containerStack.addArrangedSubview(errorLabel)
        
        addSubview(containerStack)
        
        NSLayoutConstraint.activate([
            containerStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            containerStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            containerStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32)
        ])
    }
    
    func showLoading(message: String) {
        spinner.startAnimating()
        spinner.isHidden = false
        messageLabel.text = message
        messageLabel.isHidden = false
        errorLabel.isHidden = true
    }
    
    func showError(message: String) {
        spinner.stopAnimating()
        spinner.isHidden = true
        messageLabel.isHidden = true
        errorLabel.text = message
        errorLabel.isHidden = false
    }
}

// MARK: - Photo Grid Cell

private final class PhotoGridCell: UICollectionViewCell {
    static let reuseIdentifier = "PhotoGridCell"
    
    private let imageView = UIImageView()
    private let gradientLayer = CAGradientLayer()
    private let spinner = UIActivityIndicatorView(style: .medium)
    
    private var requestID: PHImageRequestID?
    private var currentAssetID: String?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)
        
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0.0).cgColor,
            UIColor.black.withAlphaComponent(0.7).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        gradientLayer.frame = contentView.bounds
        contentView.layer.addSublayer(gradientLayer)
        
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = contentView.bounds
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        spinner.stopAnimating()
        
        if let requestID {
            PHCachingImageManager.default().cancelImageRequest(requestID)
            self.requestID = nil
        }
        currentAssetID = nil
    }
    
    func configure(with asset: PHAsset, targetSize: CGSize, cache: ImageCacheService, imageManager: PHCachingImageManager) {
        let assetID = asset.localIdentifier
        currentAssetID = assetID
        
        let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
        
        if let cached = cache.image(for: cacheKey) {
            imageView.image = cached
            return
        }
        
        spinner.startAnimating()
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        requestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            guard let self, self.currentAssetID == assetID else { return }
            
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true
            
            if let image, !isDegraded {
                cache.setImage(image, for: cacheKey)
                DispatchQueue.main.async {
                    self.imageView.image = image
                    self.spinner.stopAnimating()
                }
            }
        }
    }
}

// MARK: - Photo Group Header View

private final class PhotoGroupHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "PhotoGroupHeaderView"
    
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stackView = UIStackView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        titleLabel.font = .boldSystemFont(ofSize: 28)
        titleLabel.textColor = .label
        
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
    
    func configure(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }
}