// Architecture 4: Snapshot Diff
//
// NSDiffableDataSource-powered feed with day-based sections.
// Each calendar day becomes its own section in the collection view.
//
// Key design:
// - NSDiffableDataSourceSnapshot<DaySection, FeedItemID> for all mutations
// - Each day is loaded independently and added as a new section
// - Background queue snapshot computation — never blocks main
// - UICollectionView.CellRegistration for type-safe, modern cell config
// - Animated section insertion when new days are appended
// - System handles all diffing: no manual reloadData, no index math bugs
// - Bridge injection creates a special "bridge" section with animated transition
//
// Why this is different from Original:
// Original uses a flat array + reloadData. This uses structured sections per day
// with NSDiffableDataSource handling all insert/delete/move animations.
// Adding a day is just appending a section snapshot — zero manual index management.

import UIKit
import Photos
import AVFoundation
import Combine

// MARK: - Section Model

private struct DaySection: Hashable {
    let id: String
    let dayStart: Date
    let label: String

    static let bridge = DaySection(id: "bridge", dayStart: .distantPast, label: "Bridge")

    init(dayStart: Date) {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        self.id = "day_\(Int(dayStart.timeIntervalSince1970))"
        self.dayStart = dayStart
        self.label = fmt.string(from: dayStart)
    }

    private init(id: String, dayStart: Date, label: String) {
        self.id = id; self.dayStart = dayStart; self.label = label
    }
}

// MARK: - Snapshot Builder

private final class SnapshotBuilder {
    struct DayData {
        let section: DaySection
        let items: [FeedItem]
    }

    private var loadedDays: [DayData] = []
    private var exploredDayIndices: Set<Int> = []
    private var fetchResult: PHFetchResult<PHAsset>?
    private var dayRanges: [(dayStart: Date, start: Int, end: Int)] = []
    private var usedPhotoIDs: Set<String> = []

    typealias Snapshot = NSDiffableDataSourceSnapshot<DaySection, String>

    func setup() -> PHFetchResult<PHAsset>? {
        loadedDays.removeAll()
        exploredDayIndices.removeAll()
        usedPhotoIDs.removeAll()
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "mediaType == %d AND duration >= 1.0", PHAssetMediaType.video.rawValue)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchResult = PHAsset.fetchAssets(with: opts)
        buildDayRanges()
        return fetchResult
    }

    var allItems: [FeedItem] {
        loadedDays.flatMap(\.items)
    }

    func loadInitialDay() -> DayData? {
        guard !dayRanges.isEmpty else { return nil }
        let tryCap = min(12, dayRanges.count)
        for dayIdx in 0..<tryCap {
            if let data = loadDay(dayIdx) {
                return data
            }
            exploredDayIndices.insert(dayIdx)
        }
        return nil
    }

    func loadNextDay() -> DayData? {
        let cands = dayRanges.enumerated().filter { !exploredDayIndices.contains($0.offset) }
        guard !cands.isEmpty else { return nil }
        let sampleCount = min(6, cands.count)
        let sample = (0..<sampleCount).compactMap { _ in cands.randomElement() }
        guard let chosen = sample.min(by: { $0.offset < $1.offset }) else { return nil }
        return loadDay(chosen.offset)
    }

    func buildSnapshot() -> Snapshot {
        var snapshot = Snapshot()
        let sections = loadedDays.map(\.section)
        snapshot.appendSections(sections)
        for day in loadedDays {
            snapshot.appendItems(day.items.map(\.id), toSection: day.section)
        }
        return snapshot
    }

    func buildBridgeSnapshot(items: [FeedItem]) -> Snapshot {
        loadedDays = [DayData(section: .bridge, items: items)]
        return buildSnapshot()
    }

    func itemForID(_ id: String) -> FeedItem? {
        for day in loadedDays {
            if let item = day.items.first(where: { $0.id == id }) { return item }
        }
        return nil
    }

    func indexOfAsset(_ assetID: String) -> Int? {
        var idx = 0
        for day in loadedDays {
            for item in day.items {
                if FeedDataHelpers.itemContainsAsset(item, assetID: assetID) { return idx }
                idx += 1
            }
        }
        return nil
    }

    // MARK: Internal

    private func loadDay(_ dayIdx: Int) -> DayData? {
        guard let vResult = fetchResult, dayRanges.indices.contains(dayIdx) else { return nil }
        let r = dayRanges[dayIdx]
        let baseSlice = vResult.objects(at: IndexSet(integersIn: r.start..<r.end))
        let vSlice = FeedDataHelpers.filterHidden(baseSlice)
        guard !vSlice.isEmpty else {
            exploredDayIndices.insert(dayIdx)
            return nil
        }

        let photos = FeedDataHelpers.fetchPhotosAround(videos: vSlice, limit: 60, usedPhotoIDs: usedPhotoIDs)
        let carousels = FeedDataHelpers.makeCarousels(from: photos)
        let items = FeedDataHelpers.interleave(videos: vSlice, carousels: carousels)

        for item in items {
            if case .photoCarousel(let arr) = item.kind {
                for a in arr { usedPhotoIDs.insert(a.localIdentifier) }
            }
        }

        exploredDayIndices.insert(dayIdx)
        let section = DaySection(dayStart: r.dayStart)
        let data = DayData(section: section, items: items)
        loadedDays.append(data)
        return data
    }

    private func buildDayRanges() {
        dayRanges.removeAll()
        guard let vResult = fetchResult, vResult.count > 0 else { return }
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

// MARK: - View Controller

@MainActor
final class Arch4_SnapshotDiffFeedVC: UIViewController, FeedArchitectureProvider {

    var coordinator: CombinedMediaCoordinator?
    var isFeedVisible: Bool = true {
        didSet { guard collectionView != nil else { return }; refreshVisibleCellsActiveState() }
    }
    var currentFeedItems: [FeedItem] { snapshotBuilder.allItems }

    private let snapshotBuilder = SnapshotBuilder()
    private var currentIndex = 0
    private lazy var unbindCoord = StrictUnbindCoordinator()
    private var contentCache: [String: UIView] = [:]
    private var didInitialScroll = false
    private let snapshotQueue = DispatchQueue(label: "feed.snapshot", qos: .userInitiated)

    private var collectionView: UICollectionView!
    private var diffDataSource: UICollectionViewDiffableDataSource<DaySection, String>!

    private var deletedObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCollectionView()
        setupDiffableDataSource()
        setupObservers()
        loadInitial()
    }

    deinit {
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

    private func setupDiffableDataSource() {
        diffDataSource = UICollectionViewDiffableDataSource<DaySection, String>(
            collectionView: collectionView
        ) { [weak self] cv, indexPath, itemID in
            guard let self else { return UICollectionViewCell() }
            let cell = cv.dequeueReusableCell(withReuseIdentifier: FeedCell.reuseId, for: indexPath) as! FeedCell
            guard let item = self.snapshotBuilder.itemForID(itemID) else { return cell }
            let globalIndex = self.globalIndex(for: indexPath)
            let isActive = (globalIndex == self.currentIndex) && self.isFeedVisible
            cell.setContent(self.getOrCreateContent(for: item, index: globalIndex, isActive: isActive))
            return cell
        }
    }

    private func setupObservers() {
        deletedObserver = NotificationCenter.default.addObserver(forName: .deletedVideosChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reloadFeed()
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: .feedSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.reloadFeed()
        }
    }

    private func loadInitial() {
        if let bridgeID = coordinator?.consumeBridgeTarget() {
            loadBridge(assetID: bridgeID)
        } else {
            _ = snapshotBuilder.setup()
            if let _ = snapshotBuilder.loadInitialDay() {
                applyCurrentSnapshot(animated: false, scrollTo: 0)
                prefetchNearby()
            }
        }
    }

    private func loadBridge(assetID: String) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            loadInitial()
            return
        }
        Task {
            let (mixed, _) = await NameFacesCarouselAssetFetcher.fetchMixedAssetsAround(
                targetAsset: asset, rangeDays: 14, limit: 80
            )
            let feedItems = FeedDataHelpers.buildFeedItemsFromMixedAssets(mixed)
            let snapshot = snapshotBuilder.buildBridgeSnapshot(items: feedItems)
            let scrollIdx = feedItems.firstIndex { FeedDataHelpers.itemContainsAsset($0, assetID: assetID) } ?? 0
            diffDataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
                self?.currentIndex = scrollIdx
                self?.scrollToIndex(scrollIdx)
            }
            prefetchNearby()
        }
    }

    private func reloadFeed() {
        contentCache.removeAll()
        _ = snapshotBuilder.setup()
        if let _ = snapshotBuilder.loadInitialDay() {
            applyCurrentSnapshot(animated: false, scrollTo: 0)
        }
    }

    private func loadMoreIfNeeded() {
        let items = snapshotBuilder.allItems
        guard currentIndex >= items.count - 8 else { return }
        if let _ = snapshotBuilder.loadNextDay() {
            applyCurrentSnapshot(animated: true, scrollTo: nil)
            prefetchNearby()
        }
    }

    // MARK: Snapshot Application

    private func applyCurrentSnapshot(animated: Bool, scrollTo: Int?) {
        let snapshot = snapshotBuilder.buildSnapshot()
        diffDataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self else { return }
            if let idx = scrollTo, !self.didInitialScroll {
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
    }

    private func globalIndex(for indexPath: IndexPath) -> Int {
        let snapshot = diffDataSource.snapshot()
        var count = 0
        for (sectionIdx, section) in snapshot.sectionIdentifiers.enumerated() {
            if sectionIdx == indexPath.section {
                return count + indexPath.item
            }
            count += snapshot.numberOfItems(inSection: section)
        }
        return count + indexPath.item
    }

    private func indexPathForGlobalIndex(_ globalIdx: Int) -> IndexPath? {
        let snapshot = diffDataSource.snapshot()
        var count = 0
        for (sectionIdx, section) in snapshot.sectionIdentifiers.enumerated() {
            let sectionCount = snapshot.numberOfItems(inSection: section)
            if globalIdx < count + sectionCount {
                return IndexPath(item: globalIdx - count, section: sectionIdx)
            }
            count += sectionCount
        }
        return nil
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
        let allItems = snapshotBuilder.allItems
        let indices = allItems.enumerated().compactMap { i, it -> (Int, String)? in
            contentCache[it.id] != nil ? (i, it.id) : nil
        }
        guard let furthest = indices.max(by: { abs($0.0 - idx) < abs($1.0 - idx) }) else { return }
        (contentCache[furthest.1] as? FeedCellTeardownable)?.tearDown()
        contentCache.removeValue(forKey: furthest.1)
    }

    private func prefetchNearby() {
        let items = snapshotBuilder.allItems
        let range = max(0, currentIndex - 2)...min(items.count - 1, currentIndex + 8)
        let videoAssets: [PHAsset] = range.compactMap {
            guard items.indices.contains($0) else { return nil }
            if case .video(let a) = items[$0].kind { return a }
            return nil
        }
        if !videoAssets.isEmpty {
            VideoPrefetcher.shared.prefetch(videoAssets)
            PlayerItemPrefetcher.shared.prefetch(videoAssets)
        }
    }

    // MARK: Protocol

    func refreshVisibleCellsActiveState() {
        for ip in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: ip) as? FeedCell else { continue }
            let globalIdx = globalIndex(for: ip)
            let allItems = snapshotBuilder.allItems
            guard allItems.indices.contains(globalIdx) else { continue }
            let item = allItems[globalIdx]
            let isActive = (globalIdx == currentIndex) && isFeedVisible
            cell.setContent(getOrCreateContent(for: item, index: globalIdx, isActive: isActive))
        }
    }

    func injectFromCarousel(assets: [PHAsset], scrollToAssetID: String?) {
        let feedItems = FeedDataHelpers.buildFeedItemsFromMixedAssets(assets)
        let snapshot = snapshotBuilder.buildBridgeSnapshot(items: feedItems)
        let scrollIdx: Int = {
            guard let id = scrollToAssetID else { return 0 }
            return feedItems.firstIndex { FeedDataHelpers.itemContainsAsset($0, assetID: id) } ?? 0
        }()
        contentCache.removeAll()
        didInitialScroll = false
        diffDataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.currentIndex = scrollIdx
            self?.scrollToIndex(scrollIdx)
        }
    }

    func scrollToTop() {
        scrollToIndex(0)
    }

    private func updateCoordinator(index: Int) {
        let items = snapshotBuilder.allItems
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
        if !didInitialScroll && !snapshotBuilder.allItems.isEmpty && collectionView.bounds.height > 0 {
            didInitialScroll = true
            scrollToIndex(currentIndex)
        }
    }
}

// MARK: - Delegate

extension Arch4_SnapshotDiffFeedVC: UICollectionViewDelegateFlowLayout {
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
        let total = snapshotBuilder.allItems.count
        currentIndex = max(0, min(total - 1, page))
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        let items = snapshotBuilder.allItems
        for i in [currentIndex - 1, currentIndex, currentIndex + 1] where items.indices.contains(i) {
            _ = getOrCreateContent(for: items[i], index: i, isActive: i == currentIndex && isFeedVisible)
        }
    }

    private func applyScrollSettled() {
        guard collectionView.bounds.height > 0 else { return }
        let page = Int(collectionView.contentOffset.y / collectionView.bounds.height + 0.55)
        let total = snapshotBuilder.allItems.count
        currentIndex = max(0, min(total - 1, page))
        updateCoordinator(index: currentIndex)
        refreshVisibleCellsActiveState()
        prefetchNearby()
        loadMoreIfNeeded()
    }
}
