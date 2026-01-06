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
    
    // MARK: - Properties
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!
    
    private let imageManager = PHCachingImageManager()
    private let cache = ImageCacheService.shared
    private let grouper = PhotoGroupingService()
    
    private var photoGroups: [PhotoGroup] = []
    private var itemsBySection: [Section: [Item]] = [:]
    
    private let itemsPerRow: CGFloat = 3
    private let sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 16, right: 16)
    private let minimumInteritemSpacing: CGFloat = 10
    private let minimumLineSpacing: CGFloat = 10
    
    private var thumbnailSize: CGSize = .zero
    private let scale = UIScreen.main.scale
    
    private var loadTask: Task<Void, Never>?
    private var changeObserver: PHPhotoLibraryChangeObserver?
    
    var onPhotoPicked: PhotoPickedHandler?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("PhotosGridViewController viewDidLoad")
        
        view.backgroundColor = .systemGroupedBackground
        
        computeThumbnailSize()
        setupCollectionView()
        setupDataSource()
        registerForPhotoLibraryChanges()
        
        loadPhotos()
    }
    
    deinit {
        logger.info("PhotosGridViewController deinit")
        if let observer = changeObserver {
            PHPhotoLibrary.shared().unregisterChangeObserver(observer)
        }
        loadTask?.cancel()
    }
    
    // MARK: - Setup
    
    private func computeThumbnailSize() {
        let availableWidth = view.bounds.width - sectionInset.left - sectionInset.right
        let totalSpacing = minimumInteritemSpacing * (itemsPerRow - 1)
        let itemWidth = (availableWidth - totalSpacing) / itemsPerRow
        let dimension = floor(itemWidth * scale)
        thumbnailSize = CGSize(width: dimension, height: dimension)
        logger.debug("Computed thumbnail size: \(dimension)x\(dimension) @\(self.scale)x")
    }
    
    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.sectionInset = sectionInset
        layout.minimumInteritemSpacing = minimumInteritemSpacing
        layout.minimumLineSpacing = minimumLineSpacing
        
        let availableWidth = view.bounds.width - sectionInset.left - sectionInset.right
        let totalSpacing = minimumInteritemSpacing * (itemsPerRow - 1)
        let itemWidth = (availableWidth - totalSpacing) / itemsPerRow
        layout.itemSize = CGSize(width: itemWidth, height: itemWidth)
        layout.headerReferenceSize = CGSize(width: view.bounds.width, height: 60)
        
        logger.debug("UICollectionViewFlowLayout itemSize: \(itemWidth)x\(itemWidth)")
        
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.register(PhotoGridCell.self, forCellWithReuseIdentifier: PhotoGridCell.reuseIdentifier)
        collectionView.register(
            PhotoGroupHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: PhotoGroupHeaderView.reuseIdentifier
        )
        
        view.addSubview(collectionView)
        logger.info("UICollectionView configured and added to hierarchy")
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
            
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: PhotoGroupHeaderView.reuseIdentifier,
                for: indexPath
            ) as! PhotoGroupHeaderView
            
            let section = self.dataSource.snapshot().sectionIdentifiers[indexPath.section]
            let group = self.photoGroups[indexPath.section]
            header.configure(title: group.title, subtitle: group.subtitle)
            return header
        }
        
        logger.info("UICollectionViewDiffableDataSource configured")
    }
    
    private func registerForPhotoLibraryChanges() {
        changeObserver = PhotoLibraryService.shared.observeChanges { [weak self] in
            guard let self else { return }
            logger.info("PHPhotoLibrary change detected, reloading")
            Task { @MainActor in
                self.loadPhotos()
            }
        }
    }
    
    // MARK: - Loading
    
    private func loadPhotos() {
        loadTask?.cancel()
        logger.info("loadPhotos() started")
        
        loadTask = Task { [weak self] in
            guard let self else { return }
            
            let startTime = CFAbsoluteTimeGetCurrent()
            
            let status = await PhotoLibraryService.shared.requestAuthorization()
            guard status == .authorized || status == .limited else {
                logger.error("Photo library authorization denied: \(String(describing: status))")
                return
            }
            logger.info("Photo library authorized: \(String(describing: status))")
            
            let fetchStart = CFAbsoluteTimeGetCurrent()
            let assets = self.fetchAssets(excludingScreenshots: true, fetchLimit: 1000)
            let fetchDuration = CFAbsoluteTimeGetCurrent() - fetchStart
            logger.info("Fetched \(assets.count) assets in \(String(format: "%.3f", fetchDuration))s")
            
            guard !assets.isEmpty else {
                logger.warning("No assets found")
                await MainActor.run {
                    self.photoGroups = []
                    self.applySnapshot(groups: [])
                }
                return
            }
            
            let groupStart = CFAbsoluteTimeGetCurrent()
            let groups = await self.grouper.groupAssets(assets)
            let groupDuration = CFAbsoluteTimeGetCurrent() - groupStart
            logger.info("Grouped into \(groups.count) groups in \(String(format: "%.3f", groupDuration))s")
            
            if Task.isCancelled {
                logger.info("Load task cancelled before applying snapshot")
                return
            }
            
            await MainAactor.run {
                self.photoGroups = groups
                self.applySnapshot(groups: groups)
                
                let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
                logger.info("Total load completed in \(String(format: "%.3f", totalDuration))s")
            }
            
            self.preheatInitialAssets()
        }
    }
    
    private func fetchAssets(excludingScreenshots: Bool, fetchLimit: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = fetchLimit
        
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
        
        logger.debug("PHAsset.fetchAssets returned \(assets.count) items")
        return assets
    }
    
    private func applySnapshot(groups: [PhotoGroup]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        itemsBySection.removeAll()
        
        for group in groups {
            let section = Section.group(group.id)
            snapshot.appendSections([section])
            
            let items = group.representativeAssets.map { asset in
                Item(assetID: asset.localIdentifier, asset: asset)
            }
            snapshot.appendItems(items, toSection: section)
            itemsBySection[section] = items
        }
        
        logger.info("Applying snapshot with \(snapshot.numberOfSections) sections, \(snapshot.numberOfItems) items")
        dataSource.apply(snapshot, animatingDifferences: false)
    }
    
    private func preheatInitialAssets() {
        let assetsToHeat = photoGroups.prefix(6).flatMap { $0.representativeAssets }.prefix(36)
        guard !assetsToHeat.isEmpty else { return }
        
        logger.debug("Preheating \(assetsToHeat.count) initial assets")
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
        logger.info("Cell tapped: \(item.assetID)")
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        imageManager.requestImage(
            for: item.asset,
            targetSize: PHImageManagerMaximumSize,
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
}

// MARK: - UICollectionViewDataSourcePrefetching

extension PhotosGridViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let assets = indexPaths.compactMap { dataSource.itemIdentifier(for: $0)?.asset }
        guard !assets.isEmpty else { return }
        
        logger.debug("Prefetching \(assets.count) assets at indexPaths: \(indexPaths.map { $0.item })")
        imageManager.startCachingImages(
            for: assets,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: photoRequestOptions()
        )
    }
    
    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let assets = indexPaths.compactMap { dataSource.itemIdentifier(for: $0)?.asset }
        guard !assets.isEmpty else { return }
        
        logger.debug("Cancelling prefetch for \(assets.count) assets")
        imageManager.stopCachingImages(
            for: assets,
            targetSize: thumbnailSize,
            contentMode: .aspectFill,
            options: photoRequestOptions()
        )
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
        contentView.layer.cornerRadius = 10
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