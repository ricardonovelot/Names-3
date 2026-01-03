import SwiftUI
import UIKit
import Photos
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PhotoGrid", category: "PhotoGrid")

struct PhotoGridView: UIViewRepresentable {
    let assets: [PHAsset]
    let imageManager: PHCachingImageManager
    let onPick: (UIImage, Date?) -> Void
    let onAppearAtIndex: (Int) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        
        let layout = PinchableGridLayout()
        layout.minimumInteritemSpacing = 1
        layout.minimumLineSpacing = 1
        layout.sectionInset = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = UIColor.systemGroupedBackground
        collectionView.delegate = context.coordinator
        collectionView.prefetchDataSource = context.coordinator
        collectionView.alwaysBounceVertical = true
        collectionView.isPrefetchingEnabled = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseIdentifier)
        
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        collectionView.addGestureRecognizer(pinch)
        
        context.coordinator.configureDataSource(for: collectionView)
        
        let floatingHeader = MonthHeaderView(frame: .zero)
        floatingHeader.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(collectionView)
        containerView.addSubview(floatingHeader)
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: containerView.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            floatingHeader.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            floatingHeader.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            floatingHeader.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            floatingHeader.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        context.coordinator.collectionView = collectionView
        context.coordinator.floatingHeader = floatingHeader
        context.coordinator.containerView = containerView
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.updateAssets(assets)
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.cleanup()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            imageManager: imageManager,
            onPick: onPick,
            onAppearAtIndex: onAppearAtIndex
        )
    }
    
    final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate, UIScrollViewDelegate, PhotoCellPinchDelegate {
        let imageManager: PHCachingImageManager
        let onPick: (UIImage, Date?) -> Void
        let onAppearAtIndex: (Int) -> Void
        
        weak var collectionView: UICollectionView?
        weak var floatingHeader: MonthHeaderView?
        weak var containerView: UIView?
        
        private var dataSource: UICollectionViewDiffableDataSource<MonthSection, String>?
        private var assetsByID: [String: PHAsset] = [:]
        private var sections: [MonthSection] = []
        
        private var startZoomScale: CGFloat = 1.0
        private var previousItemSize: CGSize = .zero
        private var previousContentOffset: CGPoint = .zero
        private var pinchLocation: CGPoint = .zero
        private var isZooming: Bool = false
        
        private var transitionOriginFrame: CGRect = .zero
        private var transitionOriginImage: UIImage?
        private weak var presentedDetailVC: PhotoDetailViewController?
        
        private let imageCache = ImageCacheService.shared
        
        init(imageManager: PHCachingImageManager, onPick: @escaping (UIImage, Date?) -> Void, onAppearAtIndex: @escaping (Int) -> Void) {
            self.imageManager = imageManager
            self.onPick = onPick
            self.onAppearAtIndex = onAppearAtIndex
            super.init()
        }
        
        func configureDataSource(for collectionView: UICollectionView) {
            dataSource = UICollectionViewDiffableDataSource<MonthSection, String>(
                collectionView: collectionView
            ) { [weak self] collectionView, indexPath, identifier in
                guard let self = self else { return UICollectionViewCell() }
                
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: PhotoCell.reuseIdentifier,
                    for: indexPath
                ) as? PhotoCell else {
                    return UICollectionViewCell()
                }
                
                if let asset = self.assetsByID[identifier] {
                    let cellSize = (collectionView.collectionViewLayout as? PinchableGridLayout)?.itemSize.width ?? 240
                    let targetSize = self.optimalTargetSize(for: cellSize)
                    
                    cell.configure(
                        with: asset,
                        imageManager: self.imageManager,
                        cache: self.imageCache,
                        targetSize: targetSize
                    )
                    cell.pinchDelegate = self
                }
                
                return cell
            }
        }
        
        func updateAssets(_ newAssets: [PHAsset]) {
            var assetsByMonth: [MonthSection: [PHAsset]] = [:]
            var seenIDs = Set<String>()
            
            for asset in newAssets {
                let id = asset.localIdentifier
                guard seenIDs.insert(id).inserted else { continue }
                
                assetsByID[id] = asset
                
                guard let creationDate = asset.creationDate else { continue }
                let monthDate = monthStart(for: creationDate)
                let section = MonthSection(date: monthDate)
                
                assetsByMonth[section, default: []].append(asset)
            }
            
            sections = assetsByMonth.keys.sorted { $0.date > $1.date }
            
            var snapshot = NSDiffableDataSourceSnapshot<MonthSection, String>()
            
            for section in sections {
                snapshot.appendSections([section])
                
                if let assetsInSection = assetsByMonth[section] {
                    let sortedAssets = assetsInSection.sorted { 
                        ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
                    }
                    let ids = sortedAssets.map { $0.localIdentifier }
                    snapshot.appendItems(ids, toSection: section)
                }
            }
            
            dataSource?.apply(snapshot, animatingDifferences: false)
            updateFloatingHeader()
        }
        
        func cleanup() {
            imageManager.stopCachingImagesForAllAssets()
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let collectionView = collectionView,
                  let layout = collectionView.collectionViewLayout as? PinchableGridLayout else {
                return
            }
            
            switch gesture.state {
            case .began:
                startZoomScale = layout.zoomScale
                previousItemSize = layout.itemSize
                previousContentOffset = collectionView.contentOffset
                pinchLocation = gesture.location(in: collectionView)
                collectionView.isScrollEnabled = false
                isZooming = true
                
            case .changed:
                let cumulativeScale = gesture.scale * startZoomScale
                let clampedScale = max(0.2, min(4.0, cumulativeScale))
                
                guard abs(clampedScale - layout.zoomScale) > 0.001 else { return }
                
                let contentPointBefore = CGPoint(
                    x: previousContentOffset.x + pinchLocation.x,
                    y: previousContentOffset.y + pinchLocation.y
                )
                
                layout.zoomScale = clampedScale
                
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                collectionView.layoutIfNeeded()
                CATransaction.commit()
                
                let newItemSize = layout.itemSize
                
                let scaleX = previousItemSize.width > 0 ? newItemSize.width / previousItemSize.width : 1.0
                let scaleY = previousItemSize.height > 0 ? newItemSize.height / previousItemSize.height : 1.0
                
                let contentPointAfter = CGPoint(
                    x: contentPointBefore.x * scaleX,
                    y: contentPointBefore.y * scaleY
                )
                
                var newOffset = CGPoint(
                    x: contentPointAfter.x - pinchLocation.x,
                    y: contentPointAfter.y - pinchLocation.y
                )
                
                let maxOffsetX = max(0, collectionView.contentSize.width - collectionView.bounds.width)
                let maxOffsetY = max(0, collectionView.contentSize.height - collectionView.bounds.height)
                
                newOffset.x = max(0, min(newOffset.x, maxOffsetX))
                newOffset.y = max(0, min(newOffset.y, maxOffsetY))
                
                collectionView.contentOffset = newOffset
                
                previousItemSize = newItemSize
                previousContentOffset = newOffset
                
            case .ended, .cancelled, .failed:
                collectionView.isScrollEnabled = true
                isZooming = false
                
            @unknown default:
                break
            }
        }
        
        func photoCell(_ cell: PhotoCell, didPinch gesture: UIPinchGestureRecognizer) {
            guard let collectionView = collectionView,
                  let containerView = containerView else { return }
            
            if gesture.state == .ended {
                if gesture.scale > 1.5 {
                    presentDetailView(for: cell)
                }
            }
        }
        
        private func presentDetailView(for cell: PhotoCell) {
            guard let collectionView = collectionView,
                  let containerView = containerView,
                  let indexPath = collectionView.indexPath(for: cell),
                  indexPath.section < sections.count else { return }
            
            let section = sections[indexPath.section]
            guard let snapshot = dataSource?.snapshot() else { return }
            let items = snapshot.itemIdentifiers(inSection: section)
            guard indexPath.item < items.count else { return }
            
            let identifier = items[indexPath.item]
            guard let asset = assetsByID[identifier] else { return }
            
            transitionOriginFrame = cell.convert(cell.bounds, to: containerView)
            transitionOriginImage = cell.contentView.subviews.compactMap { ($0 as? UIImageView)?.image }.first
            
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, _ in
                guard let self = self, let image = image else { return }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let detailVC = PhotoDetailViewController(image: image, date: asset.creationDate)
                    self.presentedDetailVC = detailVC
                    
                    let animator = PhotoZoomTransitionAnimator(
                        isPresenting: true,
                        originFrame: self.transitionOriginFrame,
                        originImage: self.transitionOriginImage
                    )
                    
                    let transitionDelegate = TransitionDelegateWrapper(
                        presentAnimator: animator,
                        dismissAnimator: PhotoZoomTransitionAnimator(
                            isPresenting: false,
                            originFrame: self.transitionOriginFrame,
                            originImage: self.transitionOriginImage
                        )
                    )
                    
                    detailVC.transitioningDelegate = transitionDelegate
                    detailVC.modalPresentationStyle = .fullScreen
                    
                    objc_setAssociatedObject(detailVC, "transitionDelegate", transitionDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                    
                    if let windowScene = containerView.window?.windowScene,
                       let window = windowScene.windows.first,
                       let rootVC = window.rootViewController {
                        rootVC.present(detailVC, animated: true)
                    }
                }
            }
        }
        
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return true
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateFloatingHeader()
        }
        
        private func updateFloatingHeader() {
            guard let collectionView = collectionView,
                  let floatingHeader = floatingHeader else { return }
            
            let visibleRect = CGRect(
                x: collectionView.contentOffset.x,
                y: collectionView.contentOffset.y,
                width: collectionView.bounds.width,
                height: collectionView.bounds.height
            )
            
            let centerPoint = CGPoint(
                x: visibleRect.midX,
                y: visibleRect.minY + 100
            )
            
            if let indexPath = collectionView.indexPathForItem(at: centerPoint),
               indexPath.section < sections.count {
                let section = sections[indexPath.section]
                floatingHeader.configure(with: section.date)
                floatingHeader.alpha = 1.0
            } else if !sections.isEmpty {
                let section = sections[0]
                floatingHeader.configure(with: section.date)
                floatingHeader.alpha = 1.0
            } else {
                floatingHeader.alpha = 0.0
            }
        }
        
        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            let globalIndex = globalIndexForIndexPath(indexPath)
            notifyAppear(at: globalIndex)
        }
        
        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard indexPath.section < sections.count else { return }
            let section = sections[indexPath.section]
            
            guard let snapshot = dataSource?.snapshot() else { return }
            let items = snapshot.itemIdentifiers(inSection: section)
            guard indexPath.item < items.count else { return }
            
            let identifier = items[indexPath.item]
            guard let asset = assetsByID[identifier] else { return }
            
            requestFullImage(for: asset)
        }
        
        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let limitedPaths = Array(indexPaths.prefix(50))
            
            let cellSize = (collectionView.collectionViewLayout as? PinchableGridLayout)?.itemSize.width ?? 240
            let targetSize = optimalTargetSize(for: cellSize)
            
            let assetsToCache = limitedPaths.compactMap { indexPath -> PHAsset? in
                guard indexPath.section < sections.count else { return nil }
                let section = sections[indexPath.section]
                
                guard let snapshot = dataSource?.snapshot() else { return nil }
                let items = snapshot.itemIdentifiers(inSection: section)
                guard indexPath.item < items.count else { return nil }
                
                let id = items[indexPath.item]
                guard let asset = assetsByID[id] else { return nil }
                
                let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
                if imageCache.image(for: cacheKey) != nil {
                    return nil
                }
                
                return asset
            }
            
            guard !assetsToCache.isEmpty else { return }
            
            imageManager.startCachingImages(
                for: assetsToCache,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: nil
            )
        }
        
        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            let cellSize = (collectionView.collectionViewLayout as? PinchableGridLayout)?.itemSize.width ?? 240
            let targetSize = optimalTargetSize(for: cellSize)
            
            let assetsToStop = indexPaths.compactMap { indexPath -> PHAsset? in
                guard indexPath.section < sections.count else { return nil }
                let section = sections[indexPath.section]
                
                guard let snapshot = dataSource?.snapshot() else { return nil }
                let items = snapshot.itemIdentifiers(inSection: section)
                guard indexPath.item < items.count else { return nil }
                
                let id = items[indexPath.item]
                return assetsByID[id]
            }
            
            guard !assetsToStop.isEmpty else { return }
            
            imageManager.stopCachingImages(
                for: assetsToStop,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: nil
            )
        }
        
        @MainActor
        private func notifyAppear(at index: Int) {
            onAppearAtIndex(index)
        }
        
        private func requestFullImage(for asset: PHAsset) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, _ in
                guard let self = self, let image = image else { return }
                self.notifyPick(image: image, date: asset.creationDate)
            }
        }
        
        @MainActor
        private func notifyPick(image: UIImage, date: Date?) {
            onPick(image, date)
        }
        
        private func optimalTargetSize(for cellSize: CGFloat) -> CGSize {
            let scale = UIScreen.main.scale
            let pixelSize = cellSize * scale
            
            let targetPixels: CGFloat
            if pixelSize <= 120 {
                targetPixels = 120
            } else if pixelSize <= 180 {
                targetPixels = 180
            } else {
                targetPixels = 240
            }
            
            return CGSize(width: targetPixels, height: targetPixels)
        }
        
        private func monthStart(for date: Date) -> Date {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? date
        }
        
        private func globalIndexForIndexPath(_ indexPath: IndexPath) -> Int {
            guard let snapshot = dataSource?.snapshot() else { return 0 }
            
            var count = 0
            for (sectionIndex, section) in sections.enumerated() {
                if sectionIndex < indexPath.section {
                    count += snapshot.numberOfItems(inSection: section)
                } else {
                    count += indexPath.item
                    break
                }
            }
            return count
        }
    }
}

// MARK: - Month Section

struct MonthSection: Hashable {
    let date: Date
}

// MARK: - Month Header View

final class MonthHeaderView: UIView {
    static let reuseIdentifier = "MonthHeaderView"
    
    private let label = UILabel()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        
        label.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(label)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            label.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: blurView.contentView.centerYAnchor)
        ])
    }
    
    func configure(with date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        label.text = formatter.string(from: date)
    }
}

// MARK: - Pinchable Grid Layout

final class PinchableGridLayout: UICollectionViewFlowLayout {
    var zoomScale: CGFloat = 1.0 {
        didSet {
            guard oldValue != zoomScale else { return }
            invalidateLayout()
        }
    }
    
    override func prepare() {
        super.prepare()
        
        guard let collectionView = collectionView else { return }
        
        let availableWidth = collectionView.bounds.width - sectionInset.left - sectionInset.right
        
        let baseColumns: CGFloat = 3.0
        let columns = max(2, min(20, baseColumns / zoomScale))
        let actualColumns = round(columns)
        
        let totalSpacing = minimumInteritemSpacing * (actualColumns - 1)
        let itemWidth = max(40, (availableWidth - totalSpacing) / actualColumns)
        
        itemSize = CGSize(width: itemWidth, height: itemWidth)
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView = collectionView else { return false }
        return newBounds.width != collectionView.bounds.width
    }
}

// MARK: - Photo Cell

final class PhotoCell: UICollectionViewCell {
    static let reuseIdentifier = "PhotoCell"
    
    private let imageView = UIImageView()
    private var currentRequestID: PHImageRequestID?
    private var representedAssetIdentifier: String?
    private var currentCacheKey: String?
    
    weak var pinchDelegate: PhotoCellPinchDelegate?
    private var pinchGestureRecognizer: UIPinchGestureRecognizer!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupGesture()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        
        contentView.backgroundColor = UIColor.secondarySystemGroupedBackground
    }
    
    private func setupGesture() {
        pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGestureRecognizer.delegate = self
        contentView.addGestureRecognizer(pinchGestureRecognizer)
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        pinchDelegate?.photoCell(self, didPinch: gesture)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        if let requestID = currentRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            currentRequestID = nil
        }
        
        representedAssetIdentifier = nil
        currentCacheKey = nil
        pinchDelegate = nil
    }
    
    func configure(with asset: PHAsset, imageManager: PHCachingImageManager, cache: ImageCacheService, targetSize: CGSize) {
        let assetIdentifier = asset.localIdentifier
        representedAssetIdentifier = assetIdentifier
        
        let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
        currentCacheKey = cacheKey
        
        if let cachedImage = cache.image(for: cacheKey) {
            imageView.image = cachedImage
            return
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        currentRequestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            guard let self = self else { return }
            
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            guard !isCancelled else { return }
            
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            
            guard self.representedAssetIdentifier == assetIdentifier,
                  self.currentCacheKey == cacheKey else {
                return
            }
            
            if let image = image {
                self.imageView.image = image
                
                if !isDegraded {
                    cache.setImage(image, for: cacheKey)
                }
            }
        }
    }
}

extension PhotoCell: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

protocol PhotoCellPinchDelegate: AnyObject {
    func photoCell(_ cell: PhotoCell, didPinch gesture: UIPinchGestureRecognizer)
}

extension PhotoGridView.Coordinator {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return PhotoZoomTransitionAnimator(
            isPresenting: true,
            originFrame: transitionOriginFrame,
            originImage: transitionOriginImage
        )
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return PhotoZoomTransitionAnimator(
            isPresenting: false,
            originFrame: transitionOriginFrame,
            originImage: transitionOriginImage
        )
    }
}

// MARK: - Transition Delegate Wrapper

private final class TransitionDelegateWrapper: NSObject, UIViewControllerTransitioningDelegate {
    let presentAnimator: PhotoZoomTransitionAnimator
    let dismissAnimator: PhotoZoomTransitionAnimator
    
    init(presentAnimator: PhotoZoomTransitionAnimator, dismissAnimator: PhotoZoomTransitionAnimator) {
        self.presentAnimator = presentAnimator
        self.dismissAnimator = dismissAnimator
        super.init()
    }
    
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return presentAnimator
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return dismissAnimator
    }
}