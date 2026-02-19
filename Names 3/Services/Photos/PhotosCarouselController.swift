//
//  PhotosCarouselController.swift
//  Names 3
//
//  Encapsulates all carousel logic extracted from WelcomeFaceNamingViewController.
//  Owns assets, thumbnails, display cache, sliding window, scroll delegates, position persistence.
//

import UIKit
import Photos

// MARK: - Delegate Protocol

protocol PhotosCarouselControllerDelegate: AnyObject {
    /// Called when the centered index changes during scroll or tap. Delegate should load/display main photo.
    /// `cachedImage` is non-nil when a pre-cached display image is available for instant display.
    func photosCarouselController(_ controller: PhotosCarouselController, didChangeToIndex index: Int, asset: PHAsset, cachedImage: UIImage?)

    /// Called when scrolling has fully stopped. Delegate should run face detection, setup video player, etc.
    func photosCarouselController(_ controller: PhotosCarouselController, didFinishScrollingToIndex index: Int, asset: PHAsset)

    /// Called when the sliding window fetches more assets. Delegate may preprocess new batch.
    func photosCarouselControllerDidSlideWindow(_ controller: PhotosCarouselController, direction: PhotosCarouselController.SlideDirection)

    /// Called when assets change (slide, remove). Delegate should sync with SwiftUI via onPrioritizedAssetsDidChange.
    func photosCarouselController(_ controller: PhotosCarouselController, assetsDidChange assets: [PHAsset])

    /// Optional: provide context menu for carousel item (e.g. Delete).
    func photosCarouselController(_ controller: PhotosCarouselController, contextMenuForAssetAt index: Int) -> UIMenu?
}

extension PhotosCarouselControllerDelegate {
    func photosCarouselControllerDidSlideWindow(_ controller: PhotosCarouselController, direction: PhotosCarouselController.SlideDirection) {}
    func photosCarouselController(_ controller: PhotosCarouselController, assetsDidChange assets: [PHAsset]) {}
    func photosCarouselController(_ controller: PhotosCarouselController, contextMenuForAssetAt index: Int) -> UIMenu? { nil }
    func photosCarouselControllerDidStartScrolling(_ controller: PhotosCarouselController) {}
}

// MARK: - PhotosCarouselController

final class PhotosCarouselController: NSObject {

    enum SlideDirection {
        case forward  // Toward older
        case backward // Toward newer
    }

    // MARK: - UserDefaults Keys (match WelcomeFaceNamingViewController for compatibility)

    private let carouselPositionKey = "WelcomeFaceNaming.LastCarouselPosition"
    private let carouselPositionAssetIDKey = "WelcomeFaceNaming.LastCarouselPositionAssetID"

    // MARK: - Public API

    weak var delegate: PhotosCarouselControllerDelegate?

    /// Single source of truth for current centered index.
    private(set) var currentIndex: Int = 0

    /// Current assets. Controller owns this; sliding window may modify.
    private(set) var assets: [PHAsset] = []

    /// Collection view for the carousel strip. Add to parent view hierarchy.
    private(set) lazy var collectionView: UICollectionView = makeCollectionView()

    /// Cached display image for index (for delegate to show during scroll). Read-only.
    func cachedDisplayImage(for index: Int) -> UIImage? {
        guard isValidCarouselIndex(index) else { return nil }
        return cachedDisplayImages[index]
    }

    /// Item count for validation.
    var itemCount: Int { assets.count }

    /// True iff index is in valid range.
    func isValidCarouselIndex(_ index: Int) -> Bool {
        (0..<itemCount).contains(index)
    }

    // MARK: - Dependencies

    private let imageManager = PHCachingImageManager()
    private let imageCache = ImageCacheService.shared

    // MARK: - State

    private var windowStartIndex: Int = 0
    private var isSlidingWindow = false
    private let slideTriggerMargin = 80
    private let slideWindowChunk = 120

    private var carouselThumbnails: [UIImage?] = []
    private var thumbnailLoadingTasks: [Int: Task<Void, Never>] = [:]
    private var isProgrammaticallyScrollingCarousel = false
    private var isUserTappingCarousel = false
    private var hasUserInteractedWithCarousel = false
    private var hasAppliedInitialCarouselPosition = false
    private var carouselSelectionVisible = true

    private var cachedDisplayImages: [Int: UIImage] = [:]
    private var displayImageSize: CGSize {
        UIDevice.current.userInterfaceIdiom == .phone
            ? CGSize(width: 1024, height: 1024)
            : CGSize(width: 1440, height: 1440)
    }
    private var cacheWindowSize: Int {
        UIDevice.current.userInterfaceIdiom == .phone ? 8 : 20
    }
    private var displayCacheBuffer: Int {
        UIDevice.current.userInterfaceIdiom == .phone ? 5 : 10
    }
    private var lastCachedDisplayWindow: (start: Int, end: Int)?
    private var lastCarouselThumbnailWindow: (start: Int, end: Int)?
    private var lastEvictionCenterIndex: Int?

    private let carouselThumbnailSize = CGSize(width: 150, height: 150)
    private var stripCacheWindowSize: Int {
        UIDevice.current.userInterfaceIdiom == .phone ? 20 : 30
    }
    private let evictionScrollStride = 15
    private var thumbEvictionMargin: Int {
        UIDevice.current.userInterfaceIdiom == .phone ? 30 : 50
    }

    private var scrollCommitWorkItem: DispatchWorkItem?
    private let scrollSettleInterval: TimeInterval = 0.12
    private let thumbnailTimeout: TimeInterval = 3.0

    // MARK: - Initialization

    /// Initial scroll target: asset ID (e.g. from Feed) or date for same-day scroll.
    var initialAssetID: String?
    var initialScrollDate: Date?

    override init() {
        super.init()
    }

    // MARK: - Configuration

    /// Configure with initial assets. Call before adding to view hierarchy.
    func configure(assets: [PHAsset], windowStartIndex: Int = 0) {
        self.assets = assets
        self.windowStartIndex = windowStartIndex
        carouselThumbnails = Array(repeating: nil, count: assets.count)
        currentIndex = 0
    }

    /// Replace assets if the list changed (e.g. SwiftUI passed new list). Keeps current photo by asset ID when possible.
    func replaceAssetsIfNeeded(_ newAssets: [PHAsset]) {
        guard newAssets.count != assets.count ||
              !zip(assets, newAssets).allSatisfy({ $0.localIdentifier == $1.localIdentifier }) else { return }
        guard newAssets.count >= assets.count else { return }

        let savedAssetID = UserDefaults.standard.string(forKey: carouselPositionAssetIDKey)
        assets = newAssets
        carouselThumbnails = Array(repeating: nil, count: itemCount)
        if let id = savedAssetID, let index = newAssets.firstIndex(where: { $0.localIdentifier == id }) {
            currentIndex = index
        } else {
            currentIndex = clampCarouselIndex(currentIndex)
        }
        cachedDisplayImages.removeAll()
        lastCachedDisplayWindow = nil
        lastCarouselThumbnailWindow = nil
        collectionView.reloadData()
        scrollCarouselToCurrentIndex()
        startCachingDisplayImages(around: currentIndex)
        loadVisibleAndNearbyThumbnails()
    }

    // MARK: - Setup

    func setupCarousel() {
        carouselThumbnails = Array(repeating: nil, count: itemCount)
        collectionView.reloadData()
        loadInitialCarouselThumbnails()
        startCachingDisplayImages(around: currentIndex)
    }

    func restoreCarouselPosition() {
        if let assetID = initialAssetID, let idx = assets.firstIndex(where: { $0.localIdentifier == assetID }) {
            currentIndex = idx
            return
        }
        if initialAssetID != nil {
            currentIndex = clampCarouselIndex(0)
            return
        }
        if let targetDate = initialScrollDate {
            currentIndex = indexForDate(targetDate)
            currentIndex = clampCarouselIndex(currentIndex)
            return
        }
        guard itemCount > 0 else {
            currentIndex = 0
            return
        }
        let savedIndex = UserDefaults.standard.integer(forKey: carouselPositionKey)
        let savedAssetID = UserDefaults.standard.string(forKey: carouselPositionAssetIDKey)
        if let id = savedAssetID, let index = assets.firstIndex(where: { $0.localIdentifier == id }) {
            currentIndex = index
        } else {
            currentIndex = clampCarouselIndex(savedIndex)
        }
    }

    /// Scroll to restored position. Call after restoreCarouselPosition when assets are ready.
    func scrollToSavedPosition() {
        currentIndex = clampCarouselIndex(currentIndex)
        guard itemCount > 0 else { return }

        hasUserInteractedWithCarousel = false
        isProgrammaticallyScrollingCarousel = true
        carouselSelectionVisible = false

        scrollCarouselToCurrentIndex()

        let idx = currentIndex
        if isValidCarouselIndex(idx) {
            let asset = assets[idx]
            if let cachedImage = cachedDisplayImages[idx] {
                delegate?.photosCarouselController(self, didChangeToIndex: idx, asset: asset, cachedImage: cachedImage)
            } else if asset.mediaType == .video, let thumb = carouselThumbnails[idx] {
                delegate?.photosCarouselController(self, didChangeToIndex: idx, asset: asset, cachedImage: thumb)
            }
            delegate?.photosCarouselController(self, didFinishScrollingToIndex: idx, asset: asset)
        }
    }

    /// Mark initial position as applied (e.g. after first layout).
    func markInitialPositionApplied() {
        hasAppliedInitialCarouselPosition = true
    }

    var hasAppliedInitialPosition: Bool {
        hasAppliedInitialCarouselPosition
    }

    /// Jump to photo at index (e.g. tap). Scrolls and notifies delegate.
    func scrollToIndex(_ index: Int, animated: Bool) {
        guard isValidCarouselIndex(index) else { return }

        hasUserInteractedWithCarousel = true
        isUserTappingCarousel = true
        currentIndex = index
        saveCarouselPosition()

        collectionView.reloadData()
        isProgrammaticallyScrollingCarousel = true
        carouselSelectionVisible = false
        collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
        collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: animated)

        let asset = assets[index]
        let cached = cachedDisplayImages[index]
        delegate?.photosCarouselController(self, didChangeToIndex: index, asset: asset, cachedImage: cached)
        delegate?.photosCarouselController(self, didFinishScrollingToIndex: index, asset: asset)
    }

    /// Programmatic scroll without user interaction (e.g. refine to best photo on date).
    func scrollToIndexProgrammatically(_ index: Int, animated: Bool) {
        guard isValidCarouselIndex(index) else { return }
        currentIndex = index
        isProgrammaticallyScrollingCarousel = true
        carouselSelectionVisible = false
        collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
        collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: animated)
        loadPhotoAtCarouselIndex(index)
        startCachingDisplayImages(around: index)
    }

    /// Called when scroll animation ends (e.g. from refineToBestPhoto).
    func handleScrollAnimationEnded() {
        isUserTappingCarousel = false
        isProgrammaticallyScrollingCarousel = false
        carouselSelectionVisible = true
        UIView.performWithoutAnimation {
            collectionView.reloadItems(at: collectionView.indexPathsForVisibleItems)
        }
    }

    // MARK: - Fetch Until Saved Asset

    /// Fetches batches until the carousel contains the given asset ID. Returns true if found.
    func fetchUntilSavedAssetPresent(assetID: String) async -> Bool {
        let targetAsset = await MainActor.run {
            PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject
        }
        guard let targetAsset, let targetDate = targetAsset.creationDate else { return false }

        for _ in 0..<10 {
            let alreadyThere = await MainActor.run { assets.contains { $0.localIdentifier == assetID } }
            if alreadyThere { return true }
            let lastDate = await MainActor.run { assets.last?.creationDate }
            guard let lastDate else { break }
            let newBatch = await NameFacesCarouselAssetFetcher.fetchAssetsOlderThan(lastDate, limit: slideWindowChunk)
            guard !newBatch.isEmpty else { break }
            await MainActor.run {
                let oldCount = assets.count
                assets.append(contentsOf: newBatch)
                carouselThumbnails.append(contentsOf: Array(repeating: nil, count: newBatch.count))
                let insertPaths = (oldCount..<assets.count).map { IndexPath(item: $0, section: 0) }
                collectionView.insertItems(at: insertPaths)
            }
        }

        let firstDate = await MainActor.run { assets.first?.creationDate } ?? .distantPast
        if targetDate > firstDate {
            for _ in 0..<5 {
                let alreadyThere = await MainActor.run { assets.contains { $0.localIdentifier == assetID } }
                if alreadyThere { return true }
                let first = await MainActor.run { assets.first?.creationDate }
                guard let first else { break }
                let newBatch = await NameFacesCarouselAssetFetcher.fetchAssetsNewerThan(first, limit: slideWindowChunk)
                guard !newBatch.isEmpty else { break }
                await MainActor.run {
                    isProgrammaticallyScrollingCarousel = true
                    let oldCount = assets.count
                    let oldCenter = currentIndex
                    let dropCount = min(slideWindowChunk, oldCount)
                    assets = newBatch + Array(assets.dropLast(dropCount))
                    carouselThumbnails = Array(repeating: nil, count: newBatch.count) + Array(carouselThumbnails.dropLast(dropCount))
                    currentIndex = clampCarouselIndex(oldCenter + newBatch.count)
                    cachedDisplayImages.removeAll()
                    lastCachedDisplayWindow = nil
                    let deletePaths = (oldCount - dropCount..<oldCount).map { IndexPath(item: $0, section: 0) }
                    let insertPaths = (0..<newBatch.count).map { IndexPath(item: $0, section: 0) }
                    UIView.performWithoutAnimation {
                        collectionView.performBatchUpdates {
                            collectionView.insertItems(at: insertPaths)
                            collectionView.deleteItems(at: deletePaths)
                        }
                    }
                    scrollCarouselToCurrentIndex()
                    loadPhotoAtCarouselIndex(currentIndex)
                    startCachingDisplayImages(around: currentIndex)
                }
            }
        }

        return await MainActor.run { assets.contains { $0.localIdentifier == assetID } }
    }

    // MARK: - Position Persistence

    func saveCarouselPosition() {
        let indexToSave = currentIndex
        let assetIDToSave: String? = isValidCarouselIndex(indexToSave)
            ? assets[indexToSave].localIdentifier
            : nil
        DispatchQueue.global(qos: .utility).async { [carouselPositionKey, carouselPositionAssetIDKey] in
            UserDefaults.standard.set(indexToSave, forKey: carouselPositionKey)
            if let id = assetIDToSave {
                UserDefaults.standard.set(id, forKey: carouselPositionAssetIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: carouselPositionAssetIDKey)
            }
        }
    }

    func clearSavedPosition() {
        UserDefaults.standard.removeObject(forKey: carouselPositionKey)
        UserDefaults.standard.removeObject(forKey: carouselPositionAssetIDKey)
    }

    /// Remove asset at index (e.g. archive). Updates UI and notifies delegate.
    func removeAsset(at index: Int) {
        guard isValidCarouselIndex(index) else { return }
        assets.remove(at: index)
        let newIndex: Int
        if currentIndex == index {
            newIndex = clampCarouselIndex(index)
        } else if currentIndex > index {
            newIndex = currentIndex - 1
        } else {
            newIndex = currentIndex
        }
        carouselThumbnails.remove(at: index)
        var newCached: [Int: UIImage] = [:]
        for (k, img) in cachedDisplayImages {
            if k < index { newCached[k] = img }
            else if k > index { newCached[k - 1] = img }
        }
        cachedDisplayImages = newCached
        thumbnailLoadingTasks.removeValue(forKey: index)
        for k in thumbnailLoadingTasks.keys where k > index {
            thumbnailLoadingTasks[k - 1] = thumbnailLoadingTasks.removeValue(forKey: k)
        }
        lastCachedDisplayWindow = nil
        lastCarouselThumbnailWindow = nil
        currentIndex = newIndex
        if assets.isEmpty {
            collectionView.reloadData()
        } else {
            isProgrammaticallyScrollingCarousel = true
            collectionView.performBatchUpdates {
                collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
            } completion: { [weak self] _ in
                guard let self else { return }
                self.collectionView.layoutIfNeeded()
                let path = IndexPath(item: self.currentIndex, section: 0)
                self.collectionView.scrollToItem(at: path, at: .centeredHorizontally, animated: false)
                self.isProgrammaticallyScrollingCarousel = false
                self.collectionView.reloadItems(at: [path])
                self.loadPhotoAtCarouselIndex(self.currentIndex)
                self.startCachingDisplayImages(around: self.currentIndex)
            }
        }
        saveCarouselPosition()
        delegate?.photosCarouselController(self, assetsDidChange: assets)
    }

    // MARK: - Memory / Lifecycle

    func handleMemoryWarning() {
        cachedDisplayImages.removeAll()
        lastCachedDisplayWindow = nil
        lastCarouselThumbnailWindow = nil
        lastEvictionCenterIndex = nil
        imageManager.stopCachingImagesForAllAssets()
        let margin = 15
        let low = max(0, currentIndex - margin)
        let high = itemCount > 0 ? min(itemCount - 1, currentIndex + margin) : -1
        for i in 0..<itemCount where i < low || i > high {
            thumbnailLoadingTasks[i]?.cancel()
            thumbnailLoadingTasks.removeValue(forKey: i)
            carouselThumbnails[i] = nil
        }
    }

    // MARK: - Private: Load Photo (delegate triggers full load)

    private func loadPhotoAtCarouselIndex(_ index: Int) {
        guard isValidCarouselIndex(index) else { return }
        let asset = assets[index]
        delegate?.photosCarouselController(self, didFinishScrollingToIndex: index, asset: asset)
    }

    // MARK: - Private: Scroll & Index

    private func clampCarouselIndex(_ index: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return min(max(0, index), itemCount - 1)
    }

    private func scrollCarouselToCurrentIndex() {
        guard itemCount > 0 else { return }
        currentIndex = clampCarouselIndex(currentIndex)
        collectionView.layoutIfNeeded()
        let indexPath = IndexPath(item: currentIndex, section: 0)
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: false)
        carouselSelectionVisible = true
    }

    /// Bounds validation: returns nil when collection view has zero size.
    func findCenteredItemIndex() -> Int? {
        guard itemCount > 0 else { return nil }
        let cv = collectionView
        guard cv.bounds.width > 0, cv.bounds.height > 0 else { return nil }
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

    private func indexForDate(_ date: Date) -> Int {
        let indices = indicesOnSameDay(as: date)
        if let first = indices.first {
            return first
        }
        var bestIndex = 0
        var bestInterval: TimeInterval = .infinity
        for (index, asset) in assets.enumerated() {
            let creation = asset.creationDate ?? Date()
            let interval = abs(creation.timeIntervalSince(date))
            if interval < bestInterval {
                bestInterval = interval
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func indicesOnSameDay(as date: Date) -> [Int] {
        let calendar = Calendar.current
        let targetStart = calendar.startOfDay(for: date)
        return assets.enumerated()
            .filter { _, asset in
                guard let creation = asset.creationDate else { return false }
                return calendar.isDate(creation, inSameDayAs: targetStart)
            }
            .map(\.offset)
    }

    // MARK: - Private: Scroll Delegate Helpers

    private func commitScrollPosition() {
        scrollCommitWorkItem = nil
        guard !isProgrammaticallyScrollingCarousel, !isSlidingWindow else { return }
        guard let centeredIndex = findCenteredItemIndex(), isValidCarouselIndex(centeredIndex) else { return }
        currentIndex = centeredIndex
        saveCarouselPosition()
        startCachingDisplayImages(around: centeredIndex)
    }

    /// Controller parts of performPostScrollUpdates. Delegate handles face detection, video, etc.
    func performPostScrollUpdates(for centeredIndex: Int) {
        loadVisibleAndNearbyThumbnails()
        collectionView.reloadData()
        startCachingDisplayImages(around: centeredIndex)
        slideWindowForwardIfNeeded(centerIndex: centeredIndex)
        slideWindowBackwardIfNeeded(centerIndex: centeredIndex)
        loadPhotoAtCarouselIndex(centeredIndex)
    }

    // MARK: - Private: Collection View

    private func makeCollectionView() -> UICollectionView {
        let layout = PhotoCarouselFlowLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = UIColor.systemBackground
        cv.showsHorizontalScrollIndicator = false
        cv.decelerationRate = .fast
        cv.alwaysBounceHorizontal = true
        cv.contentInsetAdjustmentBehavior = .never
        cv.clipsToBounds = true
        cv.register(PhotoCarouselCell.self, forCellWithReuseIdentifier: PhotoCarouselCell.reuseIdentifier)
        cv.dataSource = self
        cv.delegate = self
        cv.prefetchDataSource = self
        cv.isPrefetchingEnabled = true
        return cv
    }

    // MARK: - Private: Thumbnails

    private func loadInitialCarouselThumbnails() {
        let cap = UIDevice.current.userInterfaceIdiom == .phone ? 15 : 30
        let initialCount = min(cap, itemCount)
        for i in 0..<initialCount {
            loadThumbnailAtIndex(i)
        }
    }

    private func loadThumbnailAtIndex(_ index: Int) {
        guard isValidCarouselIndex(index) else { return }
        guard carouselThumbnails[index] == nil else { return }

        thumbnailLoadingTasks[index]?.cancel()

        let task = Task {
            let asset = assets[index]
            if let thumbnail = await loadThumbnailImage(for: asset) {
                await MainActor.run {
                    guard self.isValidCarouselIndex(index) else { return }
                    self.carouselThumbnails[index] = thumbnail
                    let indexPath = IndexPath(item: index, section: 0)
                    if self.collectionView.indexPathsForVisibleItems.contains(indexPath) {
                        self.collectionView.reloadItems(at: [indexPath])
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
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        let visibleIndices = visibleIndexPaths.map { $0.item }
        guard let minVisible = visibleIndices.min(), let maxVisible = visibleIndices.max() else { return }
        let startIndex = max(0, minVisible - 10)
        let endIndex = itemCount > 0 ? min(itemCount - 1, maxVisible + 10) : -1
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
            var didResume = false
            let lock = NSLock()
            let fallback = DispatchWorkItem {
                lock.lock()
                defer { lock.unlock() }
                if !didResume {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + thumbnailTimeout, execute: fallback)
            let options = carouselThumbnailOptions()
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
                    fallback.cancel()
                    didResume = true
                    continuation.resume(returning: image)
                }
            }
        }
    }

    private func loadVideoThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            var didResume = false
            let lock = NSLock()
            let fallback = DispatchWorkItem {
                lock.lock()
                defer { lock.unlock() }
                if !didResume {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + thumbnailTimeout, execute: fallback)
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            imageManager.requestImage(
                for: asset,
                targetSize: carouselThumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                fallback.cancel()
                didResume = true
                continuation.resume(returning: image)
            }
        }
    }

    private func carouselThumbnailOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        return options
    }

    // MARK: - Private: Display Cache

    private func displayImageOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        return options
    }

    private func startCachingDisplayImages(around centerIndex: Int) {
        guard itemCount > 0 else { return }
        let startIndex = max(0, centerIndex - cacheWindowSize)
        let endIndex = min(itemCount - 1, centerIndex + cacheWindowSize)
        guard startIndex <= endIndex else { return }

        if let last = lastCachedDisplayWindow {
            var toStop: [PHAsset] = []
            for i in last.start...last.end {
                if (i < startIndex || i > endIndex), isValidCarouselIndex(i) {
                    toStop.append(assets[i])
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

        var assetsToCache: [PHAsset] = []
        for i in startIndex...endIndex {
            assetsToCache.append(assets[i])
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
            let asset = assets[i]
            let cacheKey = CacheKeyGenerator.key(for: asset, size: displayImageSize)
            if let cached = imageCache.image(for: cacheKey) {
                cachedDisplayImages[i] = cached
                continue
            }
            let index = i
            let options = displayImageOptions()
            imageManager.requestImage(
                for: asset,
                targetSize: displayImageSize,
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, info in
                guard let self, let image = image else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true
                Task {
                    let decoded = await ImageDecodingService.decodeForDisplay(image)
                    let toStore = decoded ?? image
                    await MainActor.run {
                        if isDegraded {
                            if self.cachedDisplayImages[index] == nil {
                                self.cachedDisplayImages[index] = toStore
                            }
                        } else {
                            self.imageCache.setImage(toStore, for: cacheKey)
                            self.cachedDisplayImages[index] = toStore
                        }
                    }
                }
            }
        }

        let keysToRemove = cachedDisplayImages.keys.filter { index in
            index < startIndex - displayCacheBuffer || index > endIndex + displayCacheBuffer
        }
        for key in keysToRemove {
            cachedDisplayImages.removeValue(forKey: key)
        }
        let thumbLow = max(0, centerIndex - thumbEvictionMargin)
        let thumbHigh = min(itemCount - 1, centerIndex + thumbEvictionMargin)
        for i in 0..<itemCount where (i < thumbLow || i > thumbHigh) && carouselThumbnails[i] != nil {
            carouselThumbnails[i] = nil
        }

        startCachingCarouselThumbnails(around: centerIndex)
        lastEvictionCenterIndex = centerIndex
    }

    private func startCachingCarouselThumbnails(around centerIndex: Int) {
        guard itemCount > 0 else { return }
        let stripStart = max(0, centerIndex - stripCacheWindowSize)
        let stripEnd = min(itemCount - 1, centerIndex + stripCacheWindowSize)
        guard stripStart <= stripEnd else { return }

        if let last = lastCarouselThumbnailWindow {
            var toStop: [PHAsset] = []
            for i in last.start...last.end {
                if (i < stripStart || i > stripEnd), isValidCarouselIndex(i) {
                    toStop.append(assets[i])
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
            assetsToCache.append(assets[i])
        }
        guard !assetsToCache.isEmpty else { return }
        imageManager.startCachingImages(
            for: assetsToCache,
            targetSize: carouselThumbnailSize,
            contentMode: .aspectFill,
            options: carouselThumbnailOptions()
        )
    }

    // MARK: - Private: Sliding Window

    private func slideWindowForwardIfNeeded(centerIndex: Int) {
        guard !isSlidingWindow, itemCount >= slideTriggerMargin, centerIndex >= itemCount - slideTriggerMargin else { return }
        guard let lastDate = assets.last?.creationDate else { return }
        isSlidingWindow = true
        Task {
            let newBatch = await NameFacesCarouselAssetFetcher.fetchAssetsOlderThan(lastDate, limit: slideWindowChunk)
            await MainActor.run {
                defer { isSlidingWindow = false }
                guard !newBatch.isEmpty else { return }
                isProgrammaticallyScrollingCarousel = true
                let oldCount = assets.count
                let oldCenter = currentIndex
                let dropCount = min(slideWindowChunk, oldCount)
                let deletePaths = (0..<dropCount).map { IndexPath(item: $0, section: 0) }
                let insertPaths = (oldCount - dropCount..<oldCount - dropCount + newBatch.count).map { IndexPath(item: $0, section: 0) }
                assets = Array(assets.dropFirst(dropCount)) + newBatch
                carouselThumbnails = Array(carouselThumbnails.dropFirst(dropCount)) + Array(repeating: nil, count: newBatch.count)
                (0..<dropCount).forEach { thumbnailLoadingTasks.removeValue(forKey: $0) }
                thumbnailLoadingTasks.forEach { $0.value.cancel() }
                thumbnailLoadingTasks.removeAll()
                windowStartIndex += dropCount
                currentIndex = clampCarouselIndex(max(0, oldCenter - dropCount))
                cachedDisplayImages.removeAll()
                lastCachedDisplayWindow = nil
                lastCarouselThumbnailWindow = nil
                lastEvictionCenterIndex = nil
                UIView.performWithoutAnimation {
                    collectionView.performBatchUpdates {
                        collectionView.deleteItems(at: deletePaths)
                        collectionView.insertItems(at: insertPaths)
                    }
                }
                scrollCarouselToCurrentIndex()
                loadPhotoAtCarouselIndex(currentIndex)
                startCachingDisplayImages(around: currentIndex)
                delegate?.photosCarouselControllerDidSlideWindow(self, direction: .forward)
                delegate?.photosCarouselController(self, assetsDidChange: assets)
            }
        }
    }

    private func slideWindowBackwardIfNeeded(centerIndex: Int) {
        guard !isSlidingWindow, windowStartIndex > 0, centerIndex < slideTriggerMargin else { return }
        guard let firstDate = assets.first?.creationDate else { return }
        isSlidingWindow = true
        Task {
            let newBatch = await NameFacesCarouselAssetFetcher.fetchAssetsNewerThan(firstDate, limit: slideWindowChunk)
            await MainActor.run {
                defer { isSlidingWindow = false }
                guard !newBatch.isEmpty else { return }
                isProgrammaticallyScrollingCarousel = true
                let oldCount = assets.count
                let oldCenter = currentIndex
                let dropCount = min(slideWindowChunk, oldCount)
                let deletePaths = (oldCount - dropCount..<oldCount).map { IndexPath(item: $0, section: 0) }
                let insertPaths = (0..<newBatch.count).map { IndexPath(item: $0, section: 0) }
                assets = newBatch + Array(assets.dropLast(dropCount))
                carouselThumbnails = Array(repeating: nil, count: newBatch.count) + Array(carouselThumbnails.dropLast(dropCount))
                (oldCount - dropCount..<oldCount).forEach { thumbnailLoadingTasks.removeValue(forKey: $0) }
                thumbnailLoadingTasks.forEach { $0.value.cancel() }
                thumbnailLoadingTasks.removeAll()
                windowStartIndex = max(0, windowStartIndex - dropCount)
                currentIndex = clampCarouselIndex(oldCenter + newBatch.count)
                cachedDisplayImages.removeAll()
                lastCachedDisplayWindow = nil
                lastCarouselThumbnailWindow = nil
                lastEvictionCenterIndex = nil
                UIView.performWithoutAnimation {
                    collectionView.performBatchUpdates {
                        collectionView.insertItems(at: insertPaths)
                        collectionView.deleteItems(at: deletePaths)
                    }
                }
                scrollCarouselToCurrentIndex()
                loadPhotoAtCarouselIndex(currentIndex)
                startCachingDisplayImages(around: currentIndex)
                delegate?.photosCarouselControllerDidSlideWindow(self, direction: .backward)
                delegate?.photosCarouselController(self, assetsDidChange: assets)
            }
        }
    }
}

// MARK: - UICollectionViewDataSource

extension PhotosCarouselController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        itemCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoCarouselCell.reuseIdentifier, for: indexPath) as! PhotoCarouselCell
        let thumbnail = carouselThumbnails[indexPath.item]
        let isCurrentPhoto = (indexPath.item == currentIndex) && carouselSelectionVisible
        let isVideo = isValidCarouselIndex(indexPath.item) && assets[indexPath.item].mediaType == .video
        cell.configure(with: thumbnail, isCurrentPhoto: isCurrentPhoto, isVideo: isVideo)
        if thumbnail == nil {
            loadThumbnailAtIndex(indexPath.item)
        }
        return cell
    }
}

// MARK: - UICollectionViewDelegate

extension PhotosCarouselController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        hasUserInteractedWithCarousel = true
        isUserTappingCarousel = true
        scrollToIndex(indexPath.item, animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard isValidCarouselIndex(indexPath.item) else { return nil }
        guard let menu = delegate?.photosCarouselController(self, contextMenuForAssetAt: indexPath.item) else { return nil }
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { _ in menu }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension PhotosCarouselController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
            return CGSize(width: 44, height: 44)
        }
        let size = flowLayout.itemSize
        return CGSize(width: max(44, size.width), height: max(44, size.height))
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        2
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        2
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
            return UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        }
        return flowLayout.sectionInset
    }
}

// MARK: - UIScrollViewDelegate

extension PhotosCarouselController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == collectionView else { return }
        guard !isProgrammaticallyScrollingCarousel, !isUserTappingCarousel, !isSlidingWindow else { return }
        guard hasUserInteractedWithCarousel else { return }
        guard let centeredIndex = findCenteredItemIndex(), centeredIndex != currentIndex else { return }

        let previousCenteredIndex = currentIndex
        currentIndex = centeredIndex

        scrollCommitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.commitScrollPosition()
        }
        scrollCommitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + scrollSettleInterval, execute: workItem)

        if isValidCarouselIndex(centeredIndex), let cachedImage = cachedDisplayImages[centeredIndex] {
            let asset = assets[centeredIndex]
            delegate?.photosCarouselController(self, didChangeToIndex: centeredIndex, asset: asset, cachedImage: cachedImage)
        }

        let pathsToReload = [IndexPath(item: previousCenteredIndex, section: 0), IndexPath(item: centeredIndex, section: 0)]
        UIView.performWithoutAnimation {
            collectionView.reloadItems(at: pathsToReload)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView == collectionView else { return }
        scrollCommitWorkItem?.cancel()
        scrollCommitWorkItem = nil
        hasUserInteractedWithCarousel = true
        isUserTappingCarousel = false
        isProgrammaticallyScrollingCarousel = false
        startCachingDisplayImages(around: currentIndex)
        loadVisibleAndNearbyThumbnails()
        delegate?.photosCarouselControllerDidStartScrolling(self)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView == collectionView else { return }
        scrollCommitWorkItem?.cancel()
        scrollCommitWorkItem = nil
        isUserTappingCarousel = false
        guard !isProgrammaticallyScrollingCarousel, !isSlidingWindow else { return }
        guard hasUserInteractedWithCarousel, let centeredIndex = findCenteredItemIndex() else { return }
        currentIndex = centeredIndex
        saveCarouselPosition()
        performPostScrollUpdates(for: centeredIndex)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView == collectionView, !decelerate else { return }
        scrollCommitWorkItem?.cancel()
        scrollCommitWorkItem = nil
        isUserTappingCarousel = false
        guard !isProgrammaticallyScrollingCarousel, !isSlidingWindow else { return }
        guard hasUserInteractedWithCarousel, let centeredIndex = findCenteredItemIndex() else { return }
        currentIndex = centeredIndex
        saveCarouselPosition()
        performPostScrollUpdates(for: centeredIndex)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView == collectionView else { return }
        handleScrollAnimationEnded()
    }
}

// MARK: - UICollectionViewDataSourcePrefetching

extension PhotosCarouselController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            guard isValidCarouselIndex(indexPath.item) else { continue }
            loadThumbnailAtIndex(indexPath.item)
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            thumbnailLoadingTasks[indexPath.item]?.cancel()
            thumbnailLoadingTasks.removeValue(forKey: indexPath.item)
        }
    }
}

// MARK: - PhotoCarouselFlowLayout

private final class PhotoCarouselFlowLayout: UICollectionViewFlowLayout {

    private var itemSpacing: CGFloat { 1.5 }
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
        sectionInset = UIEdgeInsets(top: 2, left: minimumEdgeInset, bottom: 2, right: minimumEdgeInset)
    }

    override func prepare() {
        super.prepare()
        guard let collectionView = collectionView else { return }
        let bounds = collectionView.bounds
        let height = bounds.height - 4
        guard height > 0 else {
            itemSize = CGSize(width: 44, height: 66)
            sectionInset = UIEdgeInsets(top: 2, left: minimumEdgeInset, bottom: 2, right: minimumEdgeInset)
            return
        }
        let itemHeight = max(66, height)
        let itemWidth = max(40, floor(itemHeight * 0.6))
        itemSize = CGSize(width: itemWidth, height: itemHeight)
        let horizontalInset = max(minimumEdgeInset, (bounds.width - itemWidth) / 2)
        sectionInset = UIEdgeInsets(top: 2, left: horizontalInset, bottom: 2, right: horizontalInset)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let cv = collectionView else { return false }
        return newBounds.size != cv.bounds.size
    }

    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        guard let collectionView = collectionView else { return proposedContentOffset }
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
        for attributes in layoutAttributes {
            let distance = abs(attributes.center.x - centerX)
            if distance < minimumDistance {
                minimumDistance = distance
                closestAttribute = attributes
            }
        }
        guard let closest = closestAttribute else { return proposedContentOffset }
        let targetX = closest.center.x - collectionView.bounds.width / 2
        let maxOffsetX = collectionView.contentSize.width - collectionView.bounds.width
        let clampedX = max(0, min(targetX, max(0, maxOffsetX)))
        return CGPoint(x: clampedX, y: proposedContentOffset.y)
    }
}

// MARK: - PhotoCarouselCell

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
        selectionRing.isHidden = !isCurrentPhoto
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.selectionRing.transform = isCurrentPhoto ? CGAffineTransform(scaleX: 1.02, y: 1.02) : .identity
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        selectionRing.isHidden = true
        videoIndicator.isHidden = true
        placeholderView.stopAnimating()
    }
}
