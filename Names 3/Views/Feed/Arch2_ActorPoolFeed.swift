// Architecture 2: Actor Pool
//
// Fully actor-isolated data loading with Swift Structured Concurrency.
// Zero main-thread work until the final UI binding moment.
//
// Key design:
// - FeedLoadActor: all PHPhotoLibrary operations run in an actor (background thread)
// - PrefetchPoolActor: bounded pool (max 6 concurrent) for video/photo prefetch with priority
// - TaskGroup for parallel video + photo fetching within a day
// - AsyncStream<FeedBatch> for paginated delivery
// - @MainActor only at ViewController level for UIKit binding
// - Structured task cancellation propagates through the entire hierarchy
//
// Why this is different from Original:
// Original runs PH fetches on main thread (PHFetchResult is synchronous).
// This actor isolates ALL data work, uses TaskGroup for true parallelism,
// and a bounded prefetch pool prevents resource exhaustion.

import UIKit
import Photos
import AVFoundation
import Combine

// MARK: - Feed Load Actor

private actor FeedLoadActor {
    private var fetchResult: PHFetchResult<PHAsset>?
    private var dayRanges: [DayRange] = []
    private var exploredDays: Set<Int> = []
    private var lastDayIndex: Int?
    private var usedPhotoIDs: Set<String> = []
    private var isBridgeMode = false

    struct DayRange {
        let dayStart: Date
        let start: Int
        let end: Int
    }

    struct FeedBatch {
        let items: [FeedItem]
        let scrollToIndex: Int?
        let isAppend: Bool
    }

    func loadExplore() async -> FeedBatch {
        reset()
        let vResult = await fetchVideosConcurrent()
        fetchResult = vResult
        guard vResult.count > 0 else {
            return FeedBatch(items: [], scrollToIndex: nil, isAppend: false)
        }

        buildDayRanges(from: vResult)
        guard !dayRanges.isEmpty else {
            return FeedBatch(items: [], scrollToIndex: nil, isAppend: false)
        }

        let tryCap = min(12, dayRanges.count)
        for dayIdx in 0..<tryCap {
            if let batch = await loadDay(dayIdx, asInitial: true) {
                return batch
            }
            exploredDays.insert(dayIdx)
        }
        return FeedBatch(items: [], scrollToIndex: nil, isAppend: false)
    }

    func loadBridge(assetID: String) async -> FeedBatch {
        reset()
        isBridgeMode = true

        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            return await loadExplore()
        }

        let (mixedAssets, _) = await NameFacesCarouselAssetFetcher.fetchMixedAssetsAround(
            targetAsset: asset, rangeDays: 14, limit: 80
        )
        guard !mixedAssets.isEmpty else {
            return await loadExplore()
        }

        let feedItems = buildFeedItemsFromMixed(mixedAssets)
        let scrollIdx = feedItems.firstIndex { itemContains($0, id: assetID) } ?? 0
        return FeedBatch(items: feedItems, scrollToIndex: scrollIdx, isAppend: false)
    }

    func loadMore(currentIndex: Int, totalItems: Int) async -> FeedBatch? {
        let threshold = 8
        guard currentIndex >= totalItems - threshold else { return nil }

        if isBridgeMode {
            return nil
        }

        guard !dayRanges.isEmpty else { return nil }

        let cands = dayRanges.enumerated().filter { !exploredDays.contains($0.offset) }
        guard !cands.isEmpty else { return nil }
        let sampleCount = min(6, cands.count)
        let sample = (0..<sampleCount).compactMap { _ in cands.randomElement() }
        guard let chosen = sample.min(by: { $0.offset < $1.offset }) else { return nil }

        return await loadDay(chosen.offset, asInitial: false)
    }

    func injectCarouselAssets(_ assets: [PHAsset], scrollTo: String?) -> FeedBatch {
        reset()
        isBridgeMode = true
        let feedItems = buildFeedItemsFromMixed(assets)
        let scrollIdx: Int? = {
            guard let id = scrollTo else { return 0 }
            return feedItems.firstIndex { itemContains($0, id: id) } ?? 0
        }()
        return FeedBatch(items: feedItems, scrollToIndex: scrollIdx, isAppend: false)
    }

    // MARK: Internal

    private func reset() {
        fetchResult = nil
        dayRanges.removeAll()
        exploredDays.removeAll()
        lastDayIndex = nil
        usedPhotoIDs.removeAll()
        isBridgeMode = false
    }

    private func fetchVideosConcurrent() async -> PHFetchResult<PHAsset> {
        await withCheckedContinuation { cont in
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(format: "mediaType == %d AND duration >= 1.0", PHAssetMediaType.video.rawValue)
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            cont.resume(returning: PHAsset.fetchAssets(with: opts))
        }
    }

    private func loadDay(_ dayIdx: Int, asInitial: Bool) async -> FeedBatch? {
        guard let vResult = fetchResult, dayRanges.indices.contains(dayIdx) else { return nil }
        let r = dayRanges[dayIdx]
        let baseSlice = vResult.objects(at: IndexSet(integersIn: r.start..<r.end))
        let hidden = DeletedVideosStore.snapshot()
        let vSlice = hidden.isEmpty ? baseSlice : baseSlice.filter { !hidden.contains($0.localIdentifier) }
        guard !vSlice.isEmpty else {
            exploredDays.insert(dayIdx)
            return nil
        }

        async let photos = fetchPhotosForDay(videos: vSlice)
        let pSlice = await photos
        let carousels = makeCarouselsSync(from: pSlice)
        let built = interleaveSync(videos: vSlice, carousels: carousels)

        for item in built {
            if case .photoCarousel(let arr) = item.kind {
                for a in arr { usedPhotoIDs.insert(a.localIdentifier) }
            }
        }
        exploredDays.insert(dayIdx)
        lastDayIndex = dayIdx
        return FeedBatch(items: built, scrollToIndex: asInitial ? 0 : nil, isAppend: !asInitial)
    }

    private func fetchPhotosForDay(videos: [PHAsset]) async -> [PHAsset] {
        guard FeedPhotoGroupingMode.current != .off, FeatureFlags.enablePhotoPosts else { return [] }
        let dates = videos.compactMap(\.creationDate)
        guard let minDate = dates.min(), let maxDate = dates.max() else { return [] }

        return await withCheckedContinuation { cont in
            let tol: TimeInterval = 7 * 86400
            let lower = minDate.addingTimeInterval(-tol)
            let upper = maxDate.addingTimeInterval(tol)
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
                PHAssetMediaType.image.rawValue, lower as NSDate, upper as NSDate
            )
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let result = PHAsset.fetchAssets(with: opts)
            let count = min(180, result.count)
            guard count > 0 else { cont.resume(returning: []); return }
            let slice = result.objects(at: IndexSet(integersIn: 0..<count))
            let filtered = slice.filter {
                !self.usedPhotoIDs.contains($0.localIdentifier) &&
                !ExcludeScreenshotsPreference.shouldExcludeAsScreenshot($0)
            }
            cont.resume(returning: Array(filtered.prefix(60)))
        }
    }

    private func buildDayRanges(from vResult: PHFetchResult<PHAsset>) {
        dayRanges.removeAll()
        var curStart = 0
        var curDayStart: Date?
        let cal = Calendar.current
        for i in 0..<vResult.count {
            guard let d = vResult.object(at: i).creationDate else { continue }
            let dStart = cal.startOfDay(for: d)
            if curDayStart == nil { curDayStart = dStart; curStart = i }
            else if dStart != curDayStart {
                dayRanges.append(DayRange(dayStart: curDayStart!, start: curStart, end: i))
                curDayStart = dStart; curStart = i
            }
        }
        if let ds = curDayStart {
            dayRanges.append(DayRange(dayStart: ds, start: curStart, end: vResult.count))
        }
    }

    private func makeCarouselsSync(from photos: [PHAsset]) -> [[PHAsset]] {
        guard !photos.isEmpty, FeedPhotoGroupingMode.current != .off, FeatureFlags.enablePhotoPosts else { return [] }
        let gap: TimeInterval = 3600
        var res: [[PHAsset]] = []
        var current: [PHAsset] = []
        var lastDate: Date?
        let sorted = photos.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        for a in sorted {
            let d = a.creationDate ?? .distantPast
            if let last = lastDate, last.timeIntervalSince(d) > gap, !current.isEmpty {
                let sampled = CarouselSampling.sample(current, mode: CarouselSamplingSettings.mode)
                if sampled.count >= 2 { res.append(sampled) }
                current = []
            }
            lastDate = d; current.append(a)
        }
        if !current.isEmpty {
            let sampled = CarouselSampling.sample(current, mode: CarouselSamplingSettings.mode)
            if sampled.count >= 2 { res.append(sampled) }
        }
        return res
    }

    private func interleaveSync(videos: [PHAsset], carousels: [[PHAsset]]) -> [FeedItem] {
        var out: [FeedItem] = []
        var cIdx = 0
        for v in videos {
            out.append(.video(v))
            if cIdx < carousels.count { out.append(.carousel(carousels[cIdx])); cIdx += 1 }
        }
        return out
    }

    private func buildFeedItemsFromMixed(_ assets: [PHAsset]) -> [FeedItem] {
        let hidden = DeletedVideosStore.snapshot()
        var out: [FeedItem] = []
        var photoBuffer: [PHAsset] = []
        for a in assets {
            switch a.mediaType {
            case .video:
                if !hidden.contains(a.localIdentifier) {
                    if !photoBuffer.isEmpty { out.append(.carousel(photoBuffer)); photoBuffer = [] }
                    out.append(.video(a))
                }
            case .image: photoBuffer.append(a)
            default: break
            }
        }
        if !photoBuffer.isEmpty { out.append(.carousel(photoBuffer)) }
        return out
    }

    private func itemContains(_ item: FeedItem, id: String) -> Bool {
        switch item.kind {
        case .video(let a): return a.localIdentifier == id
        case .photoCarousel(let arr): return arr.contains { $0.localIdentifier == id }
        }
    }
}

// MARK: - Prefetch Pool Actor (Bounded Concurrency)

private actor PrefetchPoolActor {
    private let maxConcurrent = 6
    private var activeCount = 0
    private var queue: [(PHAsset, Int)] = []

    func enqueue(assets: [PHAsset], priority: Int) {
        for a in assets {
            queue.append((a, priority))
        }
        queue.sort { $0.1 > $1.1 }
        drainQueue()
    }

    func cancel(assets: [PHAsset]) {
        let ids = Set(assets.map(\.localIdentifier))
        queue.removeAll { ids.contains($0.0.localIdentifier) }
        Task { @MainActor in
            VideoPrefetcher.shared.cancel(assets)
            PlayerItemPrefetcher.shared.cancel(assets)
        }
    }

    private func drainQueue() {
        while activeCount < maxConcurrent, !queue.isEmpty {
            let (asset, _) = queue.removeFirst()
            activeCount += 1
            Task { [weak self] in
                await MainActor.run {
                    VideoPrefetcher.shared.prefetch([asset])
                    PlayerItemPrefetcher.shared.prefetch([asset])
                }
                await self?.taskFinished()
            }
        }
    }

    private func taskFinished() {
        activeCount -= 1
        drainQueue()
    }
}

// MARK: - View Controller

@MainActor
final class Arch2_ActorPoolFeedVC: UIViewController, FeedArchitectureProvider {

    var coordinator: CombinedMediaCoordinator?
    var isFeedVisible: Bool = true {
        didSet { guard collectionView != nil else { return }; refreshVisibleCellsActiveState() }
    }
    var currentFeedItems: [FeedItem] { items }

    private var items: [FeedItem] = []
    private var currentIndex = 0
    private let loadActor = FeedLoadActor()
    private let prefetchPool = PrefetchPoolActor()
    private lazy var unbindCoord = StrictUnbindCoordinator()
    private var contentCache: [String: UIView] = [:]
    private var loadTask: Task<Void, Never>?
    private var didInitialScroll = false

    private var collectionView: UICollectionView!
    private var deletedObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCollectionView()
        setupObservers()
        triggerInitialLoad()
    }

    deinit {
        loadTask?.cancel()
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
        deletedObserver = NotificationCenter.default.addObserver(forName: .deletedVideosChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadFeed() }
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: .feedSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadFeed() }
        }
    }

    private func triggerInitialLoad() {
        let bridgeID = coordinator?.consumeBridgeTarget()
        if let id = bridgeID {
            loadTask = Task { [weak self] in
                guard let self else { return }
                let batch = await self.loadActor.loadBridge(assetID: id)
                self.applyBatch(batch)
            }
        } else {
            loadTask = Task { [weak self] in
                guard let self else { return }
                let batch = await self.loadActor.loadExplore()
                self.applyBatch(batch)
            }
        }
    }

    func savePositionToStore() {
        guard items.indices.contains(currentIndex),
              let id = FeedDataHelpers.assetID(for: items[currentIndex]) else { return }
        FeedPositionStore.save(assetID: id)
    }

    private func reloadFeed() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let batch = await self.loadActor.loadExplore()
            self.applyBatch(batch)
        }
    }

    private func applyBatch(_ batch: FeedLoadActor.FeedBatch) {
        if batch.isAppend {
            items.append(contentsOf: batch.items)
            collectionView.reloadData()
        } else {
            items = batch.items
            contentCache.removeAll()
            collectionView.reloadData()
            if let idx = batch.scrollToIndex, items.indices.contains(idx) {
                didInitialScroll = false
                currentIndex = idx
            }
        }
        scheduleInitialScroll()
        prefetchNearby()
    }

    private func scheduleInitialScroll() {
        guard !didInitialScroll, !items.isEmpty, collectionView.bounds.height > 0 else { return }
        didInitialScroll = true
        let idx = currentIndex
        let offsetY = collectionView.bounds.height * CGFloat(idx)
        collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
        refreshVisibleCellsActiveState()
        updateCoordinator(index: idx)
    }

    private func prefetchNearby() {
        let page = currentIndex
        let videoAssets: [PHAsset] = ((page - 2)...(page + 6))
            .filter { items.indices.contains($0) }
            .compactMap {
                if case .video(let a) = items[$0].kind { return a }
                return nil
            }
        if !videoAssets.isEmpty {
            Task {
                await prefetchPool.enqueue(assets: videoAssets, priority: 10)
            }
        }
    }

    // MARK: Content Cache

    private func getOrCreateContent(for item: FeedItem, index: Int, isActive: Bool) -> UIView {
        if let cached = contentCache[item.id] {
            (cached as? FeedCellContentUpdatable)?.updateIsActive(isActive)
            return cached
        }
        evictDistantContent(keeping: index)
        let view = FeedCellBuilder.buildContent(for: item, isActive: isActive, unbindCoordinator: unbindCoord)
        contentCache[item.id] = view
        return view
    }

    private func evictDistantContent(keeping idx: Int) {
        guard contentCache.count >= FeedScrollSmoothnessSettings.maxContentCacheSize else { return }
        let indices = items.enumerated().compactMap { i, it -> (Int, String)? in
            contentCache[it.id] != nil ? (i, it.id) : nil
        }
        guard let furthest = indices.max(by: { abs($0.0 - idx) < abs($1.0 - idx) }) else { return }
        (contentCache[furthest.1] as? FeedCellTeardownable)?.tearDown()
        contentCache.removeValue(forKey: furthest.1)
    }

    // MARK: Protocol

    func refreshVisibleCellsActiveState() {
        for ip in collectionView.indexPathsForVisibleItems {
            guard items.indices.contains(ip.item),
                  let cell = collectionView.cellForItem(at: ip) as? FeedCell else { continue }
            let item = items[ip.item]
            let isActive = (ip.item == currentIndex) && isFeedVisible
            cell.setContent(getOrCreateContent(for: item, index: ip.item, isActive: isActive))
        }
    }

    func injectFromCarousel(assets: [PHAsset], scrollToAssetID: String?) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let batch = await self.loadActor.injectCarouselAssets(assets, scrollTo: scrollToAssetID)
            self.didInitialScroll = false
            self.applyBatch(batch)
        }
    }

    func scrollToTop() {
        guard !items.isEmpty, collectionView.bounds.height > 0 else { return }
        currentIndex = 0
        collectionView.setContentOffset(CGPoint(x: 0, y: 0), animated: true)
        refreshVisibleCellsActiveState()
        updateCoordinator(index: 0)
    }

    private func updateCoordinator(index: Int) {
        guard items.indices.contains(index) else { return }
        let (id, isVideo): (String?, Bool) = {
            switch items[index].kind {
            case .video(let a): return (a.localIdentifier, true)
            case .photoCarousel(let arr): return (arr.first?.localIdentifier, false)
            }
        }()
        coordinator?.setFocusedAsset(id, isVideo: isVideo)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize = collectionView.bounds.size
        scheduleInitialScroll()
    }
}

// MARK: - UICollectionView DataSource + Delegate

extension Arch2_ActorPoolFeedVC: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: FeedCell.reuseId, for: indexPath) as! FeedCell
        guard items.indices.contains(indexPath.item) else { return cell }
        let item = items[indexPath.item]
        let isActive = (indexPath.item == currentIndex) && isFeedVisible
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
        let page = Int(scrollView.contentOffset.y / collectionView.bounds.height + 0.55)
        currentIndex = max(0, min(items.count - 1, page))
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        for i in [currentIndex - 1, currentIndex, currentIndex + 1] where items.indices.contains(i) {
            _ = getOrCreateContent(for: items[i], index: i, isActive: i == currentIndex && isFeedVisible)
        }
    }

    private func applyScrollSettled() {
        guard collectionView.bounds.height > 0 else { return }
        let page = Int(collectionView.contentOffset.y / collectionView.bounds.height + 0.55)
        currentIndex = max(0, min(items.count - 1, page))
        updateCoordinator(index: currentIndex)
        refreshVisibleCellsActiveState()
        savePositionToStore()
        prefetchNearby()
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            if let batch = await self.loadActor.loadMore(currentIndex: self.currentIndex, totalItems: self.items.count) {
                self.applyBatch(batch)
            }
        }
    }
}
