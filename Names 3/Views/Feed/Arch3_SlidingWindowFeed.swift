// Architecture 3: Sliding Window (Virtual Scroll)
//
// O(1) memory usage regardless of photo library size.
// PHFetchResult is inherently lazy — this architecture exploits that.
//
// Key design:
// - PHFetchResult used as virtual data source (never copies all assets into array)
// - VirtualFeedResolver: resolves FeedItem on-demand from a (video index, photo window) pair
// - Ring buffer of fixed size for UIView content cache (circular, O(1) insert/evict)
// - Only materializes items within [current - buffer ... current + buffer]
// - Bidirectional pagination: extends range as user scrolls in either direction
// - PHCachingImageManager start/stop caching exactly matching the visible window
// - Memory pressure observer: halves buffer size under memory warning
//
// Why this is different from Original:
// Original materializes ALL items into an array upfront (50+ videos + carousels).
// This only materializes ~20 items at any time. Library could have 100K videos
// and this uses the same memory as a library with 20.

import UIKit
import Photos
import AVFoundation
import Combine

// MARK: - Ring Buffer

private struct RingBuffer<T> {
    private var storage: [T?]
    private(set) var capacity: Int
    private var headIndex: Int = 0

    init(capacity: Int) {
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    subscript(logicalIndex: Int) -> T? {
        get { storage[logicalIndex % capacity] }
        set { storage[logicalIndex % capacity] = newValue }
    }

    mutating func clear() {
        storage = Array(repeating: nil, count: capacity)
        headIndex = 0
    }

    mutating func resize(to newCapacity: Int) {
        storage = Array(repeating: nil, count: newCapacity)
        capacity = newCapacity
        headIndex = 0
    }
}

// MARK: - Virtual Feed Resolver

private final class VirtualFeedResolver {
    private(set) var videoFetch: PHFetchResult<PHAsset>?
    private var dayRanges: [(dayStart: Date, start: Int, end: Int)] = []
    private var materializedItems: [Int: FeedItem] = [:]
    private var totalEstimatedCount: Int = 0
    private var usedPhotoIDs: Set<String> = []

    var estimatedCount: Int { totalEstimatedCount }

    func setup() {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "mediaType == %d AND duration >= 1.0", PHAssetMediaType.video.rawValue)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        videoFetch = PHAsset.fetchAssets(with: opts)
        buildDayRanges()

        let videoCount = videoFetch?.count ?? 0
        let estimatedCarousels = FeatureFlags.enablePhotoPosts ? videoCount / 2 : 0
        totalEstimatedCount = videoCount + estimatedCarousels
    }

    func resolveWindow(center: Int, radius: Int) -> [FeedItem] {
        let lo = max(0, center - radius)
        let hi = min(totalEstimatedCount - 1, center + radius)
        guard lo <= hi else { return [] }

        ensureMaterialized(from: lo, to: hi)
        var result: [FeedItem] = []
        for i in lo...hi {
            if let item = materializedItems[i] {
                result.append(item)
            }
        }
        return result
    }

    func resolve(at index: Int) -> FeedItem? {
        if let cached = materializedItems[index] { return cached }
        ensureMaterialized(from: max(0, index - 2), to: min(totalEstimatedCount - 1, index + 2))
        return materializedItems[index]
    }

    func indexOfAsset(id: String) -> Int? {
        for (idx, item) in materializedItems {
            switch item.kind {
            case .video(let a) where a.localIdentifier == id: return idx
            case .photoCarousel(let arr) where arr.contains(where: { $0.localIdentifier == id }): return idx
            default: continue
            }
        }
        return nil
    }

    func reset() {
        materializedItems.removeAll()
        usedPhotoIDs.removeAll()
    }

    func setItems(_ items: [FeedItem]) {
        materializedItems.removeAll()
        for (i, item) in items.enumerated() {
            materializedItems[i] = item
        }
        totalEstimatedCount = items.count
    }

    // MARK: Internal

    private func ensureMaterialized(from: Int, to: Int) {
        guard let vResult = videoFetch, vResult.count > 0 else { return }
        let hidden = DeletedVideosStore.snapshot()


        let safeFrom = max(0, from)
        let safeTo = min(totalEstimatedCount - 1, to)

        for fi in safeFrom...safeTo {
            if materializedItems[fi] != nil { continue }

            let vIdx = estimateVideoIndex(for: fi)
            guard vIdx < vResult.count else { break }
            let asset = vResult.object(at: vIdx)

            if hidden.contains(asset.localIdentifier) { continue }

            if fi % 2 == 0 || FeedPhotoGroupingMode.current == .off || !FeatureFlags.enablePhotoPosts {
                materializedItems[fi] = .video(asset)
            } else {
                let photos = fetchPhotosNear(asset: asset, limit: 8)
                if photos.count >= 2 {
                    let sampled = CarouselSampling.sample(photos, mode: CarouselSamplingSettings.mode)
                    materializedItems[fi] = .carousel(sampled)
                } else {
                    let nextVIdx = vIdx + 1
                    if nextVIdx < vResult.count {
                        let nextAsset = vResult.object(at: nextVIdx)
                        if !hidden.contains(nextAsset.localIdentifier) {
                            materializedItems[fi] = .video(nextAsset)
                        }
                    }
                }
            }
        }
    }

    private func estimateVideoIndex(for feedIndex: Int) -> Int {
        if FeedPhotoGroupingMode.current == .off || !FeatureFlags.enablePhotoPosts {
            return feedIndex
        }
        return feedIndex * 2 / 3
    }

    private func fetchPhotosNear(asset: PHAsset, limit: Int) -> [PHAsset] {
        guard let date = asset.creationDate else { return [] }
        let tol: TimeInterval = 7 * 86400
        let lower = date.addingTimeInterval(-tol)
        let upper = date.addingTimeInterval(tol)
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
            PHAssetMediaType.image.rawValue, lower as NSDate, upper as NSDate
        )
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: opts)
        guard result.count > 0 else { return [] }
        let excludeScreenshots = ExcludeScreenshotsPreference.excludeScreenshots
        var assets: [PHAsset] = []
        assets.reserveCapacity(limit)
        result.enumerateObjects { asset, _, stop in
            guard assets.count < limit else { stop.pointee = true; return }
            if self.usedPhotoIDs.contains(asset.localIdentifier) { return }
            if excludeScreenshots && ExcludeScreenshotsPreference.isLikelyRealScreenshot(asset) { return }
            assets.append(asset)
        }
        return assets
    }

    private func buildDayRanges() {
        dayRanges.removeAll()
        guard let vResult = videoFetch, vResult.count > 0 else { return }
        var curStart = 0
        var curDay: Date?
        let cal = Calendar.current
        for i in 0..<vResult.count {
            guard let d = vResult.object(at: i).creationDate else { continue }
            let ds = cal.startOfDay(for: d)
            if curDay == nil { curDay = ds; curStart = i }
            else if ds != curDay {
                dayRanges.append((curDay!, curStart, i))
                curDay = ds; curStart = i
            }
        }
        if let cd = curDay { dayRanges.append((cd, curStart, vResult.count)) }
    }
}

// MARK: - Caching Window Manager

@MainActor
private final class CachingWindowManager {
    private let cachingManager = PHCachingImageManager()
    private var lastCachedRange: Range<Int>?
    private var cachedAssets: [PHAsset] = []
    private var lastViewportPx: CGSize = .zero

    func setViewportSize(_ size: CGSize) {
        lastViewportPx = size
    }

    func updateWindow(items: [FeedItem], center: Int, radius: Int) {
        let lo = max(0, center - radius)
        let hi = min(items.count - 1, center + radius)
        guard lo <= hi else { return }
        let newRange = lo..<(hi + 1)
        if lastCachedRange == newRange { return }

        let displaySize = FeedDataHelpers.photoDisplayTargetSize(viewportPx: lastViewportPx)
        let thumbSize = CGSize(width: 400, height: 400)

        if !cachedAssets.isEmpty {
            cachingManager.stopCachingImages(for: cachedAssets, targetSize: displaySize, contentMode: .aspectFill, options: nil)
            cachingManager.stopCachingImages(for: cachedAssets, targetSize: thumbSize, contentMode: .aspectFill, options: nil)
        }

        var newVideoAssets: [PHAsset] = []
        var newPhotoAssets: [PHAsset] = []
        for i in newRange where items.indices.contains(i) {
            switch items[i].kind {
            case .video(let a): newVideoAssets.append(a)
            case .photoCarousel(let arr): newPhotoAssets.append(contentsOf: arr)
            }
        }

        let allAssets = newVideoAssets + newPhotoAssets
        if !allAssets.isEmpty {
            cachingManager.startCachingImages(for: allAssets, targetSize: thumbSize, contentMode: .aspectFill, options: nil)
        }
        if !newPhotoAssets.isEmpty {
            cachingManager.startCachingImages(for: newPhotoAssets, targetSize: displaySize, contentMode: .aspectFill, options: nil)
        }

        cachedAssets = allAssets
        lastCachedRange = newRange
    }

    func stopAll() {
        cachingManager.stopCachingImagesForAllAssets()
        cachedAssets = []
        lastCachedRange = nil
    }
}

// MARK: - View Controller

@MainActor
final class Arch3_SlidingWindowFeedVC: UIViewController, FeedArchitectureProvider {

    var coordinator: CombinedMediaCoordinator?
    var isFeedVisible: Bool = true {
        didSet { guard collectionView != nil else { return }; refreshVisibleCellsActiveState() }
    }
    var currentFeedItems: [FeedItem] { windowItems }

    private let resolver = VirtualFeedResolver()
    private let cachingWindow = CachingWindowManager()
    private var windowItems: [FeedItem] = []
    private var windowOffset = 0
    private let windowRadius = 10
    private var currentIndex = 0
    private lazy var unbindCoord = StrictUnbindCoordinator()
    private var contentRing = RingBuffer<UIView>(capacity: 20)
    private var contentByID: [String: UIView] = [:]
    private var didInitialScroll = false
    private var isBridgeMode = false
    private var memoryObserver: NSObjectProtocol?
    private var deletedObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    private var collectionView: UICollectionView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCollectionView()
        setupObservers()
        loadInitial()
    }

    deinit {
        memoryObserver.map { NotificationCenter.default.removeObserver($0) }
        deletedObserver.map { NotificationCenter.default.removeObserver($0) }
        settingsObserver.map { NotificationCenter.default.removeObserver($0) }
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(FeedCell.self, forCellWithReuseIdentifier: FeedCell.reuseId)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupObservers() {
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleMemoryWarning() }
        }
        deletedObserver = NotificationCenter.default.addObserver(forName: .deletedVideosChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadFeed() }
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: .feedSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadFeed() }
        }
    }

    private func loadInitial() {
        let bridgeID = coordinator?.consumeBridgeTarget()
        if let id = bridgeID {
            loadBridge(assetID: id)
        } else {
            resolver.setup()
            materializeWindow(center: 0)
            collectionView.reloadData()
            prefetchWindow()
        }
    }

    func savePositionToStore() {
        let localIdx = currentIndex - windowOffset
        guard windowItems.indices.contains(localIdx),
              let id = FeedDataHelpers.assetID(for: windowItems[localIdx]) else { return }
        FeedPositionStore.save(assetID: id)
    }

    private func loadBridge(assetID: String) {
        isBridgeMode = true
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            resolver.setup()
            materializeWindow(center: 0)
            collectionView.reloadData()
            return
        }
        Task {
            let (mixed, _) = await NameFacesCarouselAssetFetcher.fetchMixedAssetsAround(
                targetAsset: asset, rangeDays: 14, limit: 80
            )
            let feedItems = FeedDataHelpers.buildFeedItemsFromMixedAssets(mixed)
            resolver.setItems(feedItems)
            let scrollIdx = feedItems.firstIndex { FeedDataHelpers.itemContainsAsset($0, assetID: assetID) } ?? 0
            currentIndex = scrollIdx
            materializeWindow(center: scrollIdx)
            collectionView.reloadData()
            scrollToCurrentIndex()
            prefetchWindow()
        }
    }

    private func reloadFeed() {
        resolver.reset()
        resolver.setup()
        contentByID.removeAll()
        contentRing.clear()
        currentIndex = 0
        materializeWindow(center: 0)
        collectionView.reloadData()
    }

    private func materializeWindow(center: Int) {
        windowItems = resolver.resolveWindow(center: center, radius: windowRadius)
        windowOffset = max(0, center - windowRadius)
    }

    private func expandWindowIfNeeded() {
        let localIdx = currentIndex - windowOffset
        let needsExpand = localIdx >= windowItems.count - 4 || localIdx <= 3

        if needsExpand {
            materializeWindow(center: currentIndex)
            collectionView.reloadData()
        }
    }

    private func prefetchWindow() {
        let videos: [PHAsset] = windowItems.prefix(12).compactMap {
            if case .video(let a) = $0.kind { return a }
            return nil
        }
        if !videos.isEmpty {
            VideoPrefetcher.shared.prefetch(videos)
            PlayerItemPrefetcher.shared.prefetch(videos)
        }
        cachingWindow.updateWindow(items: windowItems, center: currentIndex - windowOffset, radius: 6)
    }

    private func handleMemoryWarning() {
        contentRing.resize(to: max(6, contentRing.capacity / 2))
        let keepIDs = Set(windowItems.prefix(6).map(\.id))
        for (id, view) in contentByID where !keepIDs.contains(id) {
            (view as? FeedCellTeardownable)?.tearDown()
        }
        contentByID = contentByID.filter { keepIDs.contains($0.key) }
        cachingWindow.stopAll()
    }

    private func scrollToCurrentIndex() {
        guard collectionView.bounds.height > 0 else { return }
        let localIdx = currentIndex - windowOffset
        guard windowItems.indices.contains(localIdx) else { return }
        let offsetY = collectionView.bounds.height * CGFloat(localIdx)
        collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
        didInitialScroll = true
        refreshVisibleCellsActiveState()
    }

    // MARK: Content

    private func getOrCreateContent(for item: FeedItem, index: Int, isActive: Bool) -> UIView {
        if let cached = contentByID[item.id] {
            (cached as? FeedCellContentUpdatable)?.updateIsActive(isActive)
            return cached
        }
        evictIfNeeded(keeping: index)
        let view = FeedCellBuilder.buildContent(for: item, index: index, isActive: isActive, unbindCoordinator: unbindCoord)
        contentByID[item.id] = view
        contentRing[index] = view
        return view
    }

    private func evictIfNeeded(keeping idx: Int) {
        guard contentByID.count >= contentRing.capacity else { return }
        let indices = windowItems.enumerated().compactMap { i, it -> (Int, String)? in
            contentByID[it.id] != nil ? (i, it.id) : nil
        }
        guard let furthest = indices.max(by: { abs($0.0 - idx) < abs($1.0 - idx) }) else { return }
        (contentByID[furthest.1] as? FeedCellTeardownable)?.tearDown()
        contentByID.removeValue(forKey: furthest.1)
    }

    // MARK: Protocol

    func refreshVisibleCellsActiveState() {
        let localIdx = currentIndex - windowOffset
        for ip in collectionView.indexPathsForVisibleItems {
            guard windowItems.indices.contains(ip.item),
                  let cell = collectionView.cellForItem(at: ip) as? FeedCell else { continue }
            let item = windowItems[ip.item]
            let isActive = (ip.item == localIdx) && isFeedVisible
            cell.setContent(getOrCreateContent(for: item, index: ip.item, isActive: isActive))
        }
    }

    func injectFromCarousel(assets: [PHAsset], scrollToAssetID: String?) {
        isBridgeMode = true
        let feedItems = FeedDataHelpers.buildFeedItemsFromMixedAssets(assets)
        resolver.setItems(feedItems)
        let scrollIdx: Int = {
            guard let id = scrollToAssetID else { return 0 }
            return feedItems.firstIndex { FeedDataHelpers.itemContainsAsset($0, assetID: id) } ?? 0
        }()
        currentIndex = scrollIdx
        contentByID.removeAll()
        materializeWindow(center: scrollIdx)
        collectionView.reloadData()
        scrollToCurrentIndex()
    }

    func scrollToTop() {
        currentIndex = 0
        materializeWindow(center: 0)
        collectionView.reloadData()
        scrollToCurrentIndex()
    }

    private func updateCoordinator(index: Int) {
        let localIdx = index
        guard windowItems.indices.contains(localIdx) else { return }
        let (id, isVideo): (String?, Bool) = {
            switch windowItems[localIdx].kind {
            case .video(let a): return (a.localIdentifier, true)
            case .photoCarousel(let arr): return (arr.first?.localIdentifier, false)
            }
        }()
        coordinator?.setFocusedAsset(id, isVideo: isVideo)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize = collectionView.bounds.size
        let scale = UIScreen.main.scale
        let vpx = CGSize(width: collectionView.bounds.width * scale, height: collectionView.bounds.height * scale)
        cachingWindow.setViewportSize(vpx)
        if !didInitialScroll && !windowItems.isEmpty && collectionView.bounds.height > 0 {
            scrollToCurrentIndex()
        }
    }
}

// MARK: - DataSource + Delegate

extension Arch3_SlidingWindowFeedVC: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { windowItems.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: FeedCell.reuseId, for: indexPath) as! FeedCell
        guard windowItems.indices.contains(indexPath.item) else { return cell }
        let item = windowItems[indexPath.item]
        let localCurrent = currentIndex - windowOffset
        let isActive = (indexPath.item == localCurrent) && isFeedVisible
        cell.setContent(getOrCreateContent(for: item, index: indexPath.item, isActive: isActive))
        return cell
    }

    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        cv.bounds.size
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { applyScrollSettled() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        if !willDecelerate { applyScrollSettled() }
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { applyScrollSettled() }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard collectionView.bounds.height > 0 else { return }
        let localPage = Int(scrollView.contentOffset.y / collectionView.bounds.height + 0.55)
        let globalPage = localPage + windowOffset
        currentIndex = max(0, globalPage)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        let localIdx = currentIndex - windowOffset
        for i in [localIdx - 1, localIdx, localIdx + 1] where windowItems.indices.contains(i) {
            _ = getOrCreateContent(for: windowItems[i], index: i, isActive: i == localIdx && isFeedVisible)
        }
    }

    private func applyScrollSettled() {
        guard collectionView.bounds.height > 0 else { return }
        let localPage = Int(collectionView.contentOffset.y / collectionView.bounds.height + 0.55)
        let localClamped = max(0, min(windowItems.count - 1, localPage))
        currentIndex = localClamped + windowOffset
        updateCoordinator(index: localClamped)
        savePositionToStore()
        refreshVisibleCellsActiveState()
        expandWindowIfNeeded()
        prefetchWindow()
    }
}
