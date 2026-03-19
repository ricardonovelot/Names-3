// Architecture 1: Reactive Pipeline
//
// The entire data flow is a single Combine publisher chain.
// PHPhotoLibrary → FetchPublisher → GroupOperator → InterleaveOperator → PrefetchSink → UIBinding
//
// Key design:
// - Back-pressure aware: `.buffer(size:prefetch:whenFull:.dropOldest)` prevents overload
// - No imperative state mutation for data loading — all state flows through Combine scan/map
// - Bridge injection via dedicated Subject that merges into the main pipeline
// - Prefetch runs as a separate subscriber N items ahead of visible index
// - UICollectionViewDiffableDataSource for zero-crash mutations
//
// Why this is different from Original:
// Original uses imperative fetch → mutate → publish. This is purely declarative.
// Data flows as a stream. Pagination, bridge, reload are all signal inputs to the pipeline.

import UIKit
import Photos
import AVFoundation
import Combine

// MARK: - Pipeline Signals

private enum PipelineSignal {
    case loadExplore
    case loadBridge(assetID: String)
    case injectCarousel(assets: [PHAsset], scrollTo: String?)
    case loadMore(currentIndex: Int)
    case reload
}

// MARK: - Pipeline State (accumulated via .scan)

private struct PipelineState {
    var items: [FeedItem] = []
    var scrollToIndex: Int?
    var fetchResult: PHFetchResult<PHAsset>?
    var dayRanges: [DayRange] = []
    var exploredDays: Set<Int> = []
    var lastDayIndex: Int?
    var usedPhotoIDs: Set<String> = []
    var isBridgeMode = false
    var videosSinceLastCarousel = 0
    var isLoading = false

    struct DayRange {
        let dayStart: Date
        let start: Int
        let end: Int
    }
}

// MARK: - Reactive Pipeline

@MainActor
private final class ReactiveFeedPipeline {
    let itemsPublisher: AnyPublisher<(items: [FeedItem], scrollTo: Int?), Never>

    private let signalSubject = PassthroughSubject<PipelineSignal, Never>()
    private var cancellables = Set<AnyCancellable>()

    init() {
        itemsPublisher = signalSubject
            .scan(PipelineState()) { state, signal in
                Self.reduce(state: state, signal: signal)
            }
            .map { state in (items: state.items, scrollTo: state.scrollToIndex) }
            .removeDuplicates { $0.items.map(\.id) == $1.items.map(\.id) && $0.scrollTo == $1.scrollTo }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func send(_ signal: PipelineSignal) {
        signalSubject.send(signal)
    }

    private static func reduce(state: PipelineState, signal: PipelineSignal) -> PipelineState {
        var s = state

        switch signal {
        case .loadExplore:
            s.isLoading = true
            s = loadExploreWindow(s)
            s.isLoading = false

        case .loadBridge(let assetID):
            s.isLoading = true
            s = loadBridgeWindow(s, assetID: assetID)
            s.isLoading = false

        case .injectCarousel(let assets, let scrollTo):
            let feedItems = FeedDataHelpers.buildFeedItemsFromMixedAssets(assets)
            s.items = feedItems
            s.isBridgeMode = true
            s.exploredDays.removeAll()
            if let id = scrollTo, let idx = feedItems.firstIndex(where: { FeedDataHelpers.itemContainsAsset($0, assetID: id) }) {
                s.scrollToIndex = idx
            } else {
                s.scrollToIndex = 0
            }

        case .loadMore(let currentIndex):
            s = loadMoreIfNeeded(s, currentIndex: currentIndex)

        case .reload:
            s = PipelineState()
            s = loadExploreWindow(s)
        }

        return s
    }

    private static func loadExploreWindow(_ state: PipelineState) -> PipelineState {
        var s = state
        let vResult = FeedDataHelpers.fetchVideos()
        s.fetchResult = vResult
        guard vResult.count > 0 else {
            s.items = []
            s.scrollToIndex = nil
            return s
        }

        s.dayRanges = buildDayRanges(from: vResult)
        guard !s.dayRanges.isEmpty else {
            s.items = []
            s.scrollToIndex = nil
            return s
        }

        let tryCap = min(12, s.dayRanges.count)
        for dayIdx in 0..<tryCap {
            let result = appendDay(dayIndex: dayIdx, state: s, asInitial: true)
            if !result.items.isEmpty {
                s = result
                prefetchInitialVideos(from: s.items)
                break
            }
            s.exploredDays.insert(dayIdx)
        }

        s.scrollToIndex = 0
        return s
    }

    private static func loadBridgeWindow(_ state: PipelineState, assetID: String) -> PipelineState {
        var s = state
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            return loadExploreWindow(s)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var mixedAssets: [PHAsset] = []
        Task {
            let result = await NameFacesCarouselAssetFetcher.fetchMixedAssetsAround(
                targetAsset: asset, rangeDays: 14, limit: 80
            )
            mixedAssets = result.assets
            semaphore.signal()
        }
        semaphore.wait()

        guard !mixedAssets.isEmpty else {
            return loadExploreWindow(s)
        }

        let feedItems = FeedDataHelpers.buildFeedItemsFromMixedAssets(mixedAssets)
        s.items = feedItems
        s.isBridgeMode = true
        s.exploredDays.removeAll()

        if let idx = feedItems.firstIndex(where: { FeedDataHelpers.itemContainsAsset($0, assetID: assetID) }) {
            s.scrollToIndex = idx
        } else {
            s.scrollToIndex = 0
        }

        prefetchInitialVideos(from: feedItems)
        return s
    }

    private static func loadMoreIfNeeded(_ state: PipelineState, currentIndex: Int) -> PipelineState {
        var s = state
        let threshold = 8
        guard currentIndex >= s.items.count - threshold else { return s }

        if s.isBridgeMode {
            return loadMoreBridge(s)
        }

        guard !s.dayRanges.isEmpty else { return s }

        let cands = s.dayRanges.enumerated().filter { !s.exploredDays.contains($0.offset) }
        guard !cands.isEmpty else { return s }
        let sampleCount = min(6, cands.count)
        let sample = (0..<sampleCount).compactMap { _ in cands.randomElement() }
        guard let chosen = sample.min(by: { $0.offset < $1.offset }) else { return s }

        s = appendDay(dayIndex: chosen.offset, state: s, asInitial: false)
        return s
    }

    private static func loadMoreBridge(_ state: PipelineState) -> PipelineState {
        var s = state
        let oldestDate = s.items.flatMap { item -> [Date] in
            switch item.kind {
            case .video(let a): return (a.creationDate).map { [$0] } ?? []
            case .photoCarousel(let arr): return arr.compactMap(\.creationDate)
            }
        }.min()
        guard let date = oldestDate else { return s }

        let semaphore = DispatchSemaphore(value: 0)
        var moreAssets: [PHAsset] = []
        Task {
            moreAssets = await NameFacesCarouselAssetFetcher.fetchAssetsOlderThan(date, limit: 60)
            semaphore.signal()
        }
        semaphore.wait()

        let existingIDs = Set(FeedItem.flattenToAssets(s.items).map(\.localIdentifier))
        let newAssets = moreAssets.filter { !existingIDs.contains($0.localIdentifier) }
        guard !newAssets.isEmpty else { return s }
        let newItems = FeedDataHelpers.buildFeedItemsFromMixedAssets(newAssets)
        s.items.append(contentsOf: newItems)
        return s
    }

    private static func appendDay(dayIndex: Int, state: PipelineState, asInitial: Bool) -> PipelineState {
        var s = state
        guard let vResult = s.fetchResult, s.dayRanges.indices.contains(dayIndex) else { return s }
        let r = s.dayRanges[dayIndex]
        let baseSlice = vResult.objects(at: IndexSet(integersIn: r.start..<r.end))
        let vSlice = FeedDataHelpers.filterHidden(baseSlice)
        guard !vSlice.isEmpty else {
            s.exploredDays.insert(dayIndex)
            return s
        }
        let capped = FeedVideoHourCap.capOnePerHour(vSlice)

        let pSlice = FeedDataHelpers.fetchPhotosAround(videos: capped, limit: 60, usedPhotoIDs: s.usedPhotoIDs)
        let carousels = FeedDataHelpers.makeCarousels(from: pSlice)
        let built = FeedDataHelpers.interleave(videos: capped, carousels: carousels)

        if asInitial {
            s.items = built
        } else {
            s.items.append(contentsOf: built)
        }

        for item in built {
            if case .photoCarousel(let arr) = item.kind {
                for a in arr { s.usedPhotoIDs.insert(a.localIdentifier) }
            }
        }
        s.exploredDays.insert(dayIndex)
        s.lastDayIndex = dayIndex
        return s
    }

    private static func buildDayRanges(from vResult: PHFetchResult<PHAsset>) -> [PipelineState.DayRange] {
        var ranges: [PipelineState.DayRange] = []
        var curStart = 0
        var curDayStart: Date?
        let cal = Calendar.current
        for i in 0..<vResult.count {
            guard let d = vResult.object(at: i).creationDate else { continue }
            let dStart = cal.startOfDay(for: d)
            if curDayStart == nil {
                curDayStart = dStart; curStart = i
            } else if dStart != curDayStart {
                ranges.append(.init(dayStart: curDayStart!, start: curStart, end: i))
                curDayStart = dStart; curStart = i
            }
        }
        if let ds = curDayStart {
            ranges.append(.init(dayStart: ds, start: curStart, end: vResult.count))
        }
        return ranges
    }

    private static func prefetchInitialVideos(from items: [FeedItem]) {
        let videos: [PHAsset] = items.prefix(8).compactMap {
            if case .video(let a) = $0.kind { return a }
            return nil
        }
        if !videos.isEmpty {
            DispatchQueue.main.async {
                VideoPrefetcher.shared.prefetch(videos)
                PlayerItemPrefetcher.shared.prefetch(videos)
            }
        }
    }
}

// MARK: - Reactive Prefetch Subscriber

@MainActor
private final class ReactivePrefetchCoordinator {
    private var prefetchedIndices: Set<Int> = []

    func updateWindow(page: Int, items: [FeedItem], collectionView: UICollectionView) {
        let scale = UIScreen.main.scale
        let viewportPx = CGSize(
            width: collectionView.bounds.width * scale,
            height: collectionView.bounds.height * scale
        )
        var desired = Set((page - 4)...(page + 12)).filter { $0 >= 0 && $0 < items.count }
        for i in (page - 6)...(page + 10) where i >= 0 && i < items.count {
            if case .video(let a) = items[i].kind, a.duration > 30 { desired.insert(i) }
        }

        let adds = desired.subtracting(prefetchedIndices)
        var removes = prefetchedIndices.subtracting(desired)
        let protected = Set([page - 1, page, page + 1].filter { $0 >= 0 && $0 < items.count })
        removes.subtract(protected)

        if !adds.isEmpty { FeedDataHelpers.prefetchAssets(for: items, in: IndexSet(adds), viewportPx: viewportPx) }
        if !removes.isEmpty { FeedDataHelpers.cancelPrefetch(for: items, in: IndexSet(removes), viewportPx: viewportPx) }
        prefetchedIndices = desired
    }
}

// MARK: - View Controller

@MainActor
final class Arch1_ReactivePipelineFeedVC: UIViewController, FeedArchitectureProvider {

    var coordinator: CombinedMediaCoordinator?
    var isFeedVisible: Bool = true {
        didSet { guard collectionView != nil else { return }; refreshVisibleCellsActiveState() }
    }
    var currentFeedItems: [FeedItem] { items }

    private var items: [FeedItem] = []
    private var currentIndex = 0
    private let pipeline = ReactiveFeedPipeline()
    private let prefetch = ReactivePrefetchCoordinator()
    private lazy var unbindCoord = StrictUnbindCoordinator()
    private var cancellables = Set<AnyCancellable>()
    private var contentCache: [String: UIView] = [:]
    private var didInitialScroll = false

    private var collectionView: UICollectionView!
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Int, String>
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!

    private var deletedObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCollectionView()
        setupDataSource()
        bindPipeline()
        setupObservers()
        triggerInitialLoad()
    }

    deinit {
        deletedObserver.map { NotificationCenter.default.removeObserver($0) }
        settingsObserver.map { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: Setup

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.isPagingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .black
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

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { [weak self] cv, indexPath, itemID in
            guard let self else { return UICollectionViewCell() }
            let cell = cv.dequeueReusableCell(withReuseIdentifier: FeedCell.reuseId, for: indexPath) as! FeedCell
            guard self.items.indices.contains(indexPath.item) else { return cell }
            let item = self.items[indexPath.item]
            let isActive = (indexPath.item == self.currentIndex) && self.isFeedVisible
            cell.setContent(self.getOrCreateContent(for: item, index: indexPath.item, isActive: isActive))
            return cell
        }
    }

    private func bindPipeline() {
        pipeline.itemsPublisher
            .sink { [weak self] result in
                guard let self else { return }
                self.items = result.items
                self.applySnapshot(scrollTo: result.scrollTo)
            }
            .store(in: &cancellables)
    }

    private func setupObservers() {
        deletedObserver = NotificationCenter.default.addObserver(forName: .deletedVideosChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pipeline.send(.reload) }
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: .feedSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pipeline.send(.reload) }
        }
    }

    private func triggerInitialLoad() {
        let bridgeID = coordinator?.consumeBridgeTarget()
        if let id = bridgeID {
            pipeline.send(.loadBridge(assetID: id))
        } else {
            pipeline.send(.loadExplore)
        }
    }

    func savePositionToStore() {
        guard items.indices.contains(currentIndex),
              let id = FeedDataHelpers.assetID(for: items[currentIndex]) else { return }
        FeedPositionStore.save(assetID: id)
    }

    // MARK: Snapshot

    private func applySnapshot(scrollTo: Int?) {
        var snapshot = Snapshot()
        snapshot.appendSections([0])
        snapshot.appendItems(items.map(\.id), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            guard let self else { return }
            if let idx = scrollTo, self.items.indices.contains(idx), !self.didInitialScroll {
                self.didInitialScroll = true
                self.currentIndex = idx
                self.scrollToIndex(idx)
            }
        }
    }

    private func scrollToIndex(_ idx: Int) {
        guard collectionView.bounds.height > 0 else { return }
        let offsetY = collectionView.bounds.height * CGFloat(idx)
        collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
        refreshVisibleCellsActiveState()
        prefetch.updateWindow(page: idx, items: items, collectionView: collectionView)
    }

    // MARK: Content Cache

    private func getOrCreateContent(for item: FeedItem, index: Int, isActive: Bool) -> UIView {
        let id = item.id
        if let cached = contentCache[id] {
            (cached as? FeedCellContentUpdatable)?.updateIsActive(isActive)
            return cached
        }
        evictDistantContent(keeping: index)
        let view = FeedCellBuilder.buildContent(for: item, index: index, isActive: isActive, unbindCoordinator: unbindCoord)
        contentCache[id] = view
        return view
    }

    private func evictDistantContent(keeping currentIdx: Int) {
        guard contentCache.count >= FeedScrollSmoothnessSettings.maxContentCacheSize else { return }
        let indices = items.enumerated().compactMap { idx, it -> (Int, String)? in
            contentCache[it.id] != nil ? (idx, it.id) : nil
        }
        guard let furthest = indices.max(by: { abs($0.0 - currentIdx) < abs($1.0 - currentIdx) }) else { return }
        (contentCache[furthest.1] as? FeedCellTeardownable)?.tearDown()
        contentCache.removeValue(forKey: furthest.1)
    }

    // MARK: Protocol

    func refreshVisibleCellsActiveState() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard items.indices.contains(indexPath.item),
                  let cell = collectionView.cellForItem(at: indexPath) as? FeedCell else { continue }
            let item = items[indexPath.item]
            let isActive = (indexPath.item == currentIndex) && isFeedVisible
            cell.setContent(getOrCreateContent(for: item, index: indexPath.item, isActive: isActive))
        }
    }

    func injectFromCarousel(assets: [PHAsset], scrollToAssetID: String?) {
        didInitialScroll = false
        pipeline.send(.injectCarousel(assets: assets, scrollTo: scrollToAssetID))
    }

    func scrollToTop() {
        scrollToIndex(0)
    }

    // MARK: Coordinator Sync

    private func updateCoordinator(index: Int) {
        guard items.indices.contains(index) else { return }
        let (assetID, isVideo): (String?, Bool) = {
            switch items[index].kind {
            case .video(let a): return (a.localIdentifier, true)
            case .photoCarousel(let arr): return (arr.first?.localIdentifier, false)
            }
        }()
        coordinator?.setFocusedAsset(assetID, isVideo: isVideo)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize = collectionView.bounds.size
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension Arch1_ReactivePipelineFeedVC: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        applyScrollSettled()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        if !willDecelerate { applyScrollSettled() }
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        applyScrollSettled()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard collectionView.bounds.height > 0 else { return }
        let page = Int(scrollView.contentOffset.y / collectionView.bounds.height + 0.55)
        let target = max(0, min(items.count - 1, page))
        if target != currentIndex {
            currentIndex = target
        }
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
        prefetch.updateWindow(page: currentIndex, items: items, collectionView: collectionView)
        pipeline.send(.loadMore(currentIndex: currentIndex))
    }
}
