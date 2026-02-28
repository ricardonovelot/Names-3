//
//  FeedPagedCollectionViewController.swift
//  Names 3
//
//  Pure UIKit paged vertical collection for the feed. Uses UIView content (no SwiftUI).
//

import UIKit
import Photos

/// Protocol for feed cell content that can be updated without recreation (preserves video playback).
protocol FeedCellContentUpdatable: UIView {
    func updateIsActive(_ isActive: Bool)
}

/// Protocol for feed cell content that must be torn down when evicted from cache.
protocol FeedCellTeardownable: UIView {
    func tearDown()
}

final class FeedPagedCollectionViewController: UICollectionViewController, UICollectionViewDataSourcePrefetching, UICollectionViewDelegateFlowLayout {

    var items: [FeedItem] = []
    var idProvider: (FeedItem) -> String = { $0.id }
    var contentBuilder: (Int, FeedItem, Bool) -> UIView = { _, _, _ in UIView() }
    private var contentCache: [String: UIView] = [:]
    var onPrefetch: (IndexSet, CGSize) -> Void = { _, _ in }
    var onCancelPrefetch: (IndexSet, CGSize) -> Void = { _, _ in }
    var isPageReady: (Int) -> Bool = { _ in true }
    var onIndexChange: (Int) -> Void = { _ in }

    /// When set, used instead of (currentIndex == indexPath.item) for isActive. Enables parent to
    /// incorporate feed visibility (e.g. Feed↔Carousel mode switch) so video cells stay paused when hidden.
    var effectiveIsActive: ((Int, Int) -> Bool)?

    var initialIndexOverride: Int?
    private var currentIndex: Int = 0
    private var didInitialScroll = false
    private var prefetchedIndices: Set<Int> = []
    private var activeIndexUpdate: ((Int) -> Void)?
    init(items: [FeedItem], index: Int, idProvider: @escaping (FeedItem) -> String, contentBuilder: @escaping (Int, FeedItem, Bool) -> UIView, onPrefetch: @escaping (IndexSet, CGSize) -> Void, onCancelPrefetch: @escaping (IndexSet, CGSize) -> Void, isPageReady: @escaping (Int) -> Bool, onIndexChange: @escaping (Int) -> Void) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        super.init(collectionViewLayout: layout)
        self.items = items
        self.currentIndex = index
        self.idProvider = idProvider
        self.contentBuilder = contentBuilder
        self.onPrefetch = onPrefetch
        self.onCancelPrefetch = onCancelPrefetch
        self.isPageReady = isPageReady
        self.onIndexChange = onIndexChange
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setActiveIndexUpdate(_ block: ((Int) -> Void)?) {
        activeIndexUpdate = block
    }

    func updateItems(_ newItems: [FeedItem]) {
        let changed = newItems.map(idProvider) != items.map(idProvider)
        items = newItems
        if changed {
            let newIds = Set(newItems.map(idProvider))
            for (key, view) in contentCache where !newIds.contains(key) {
                (view as? FeedCellTeardownable)?.tearDown()
            }
            contentCache = contentCache.filter { key, _ in newIds.contains(key) }
            collectionView.reloadData()
            prefetchedIndices = []
        }
    }

    private static let maxContentCacheSize = 7

    private func getOrCreateContent(for item: FeedItem, index: Int, isActive: Bool) -> UIView {
        let id = idProvider(item)
        if let cached = contentCache[id] {
            if let updatable = cached as? FeedCellContentUpdatable {
                updatable.updateIsActive(isActive)
            }
            return cached
        }
        evictDistantContentIfNeeded(keeping: index)
        let view = contentBuilder(index, item, isActive)
        contentCache[id] = view
        return view
    }

    private func evictDistantContentIfNeeded(keeping currentIndex: Int) {
        guard contentCache.count >= Self.maxContentCacheSize else { return }
        let indices = items.enumerated().compactMap { idx, it -> (Int, String)? in
            let id = idProvider(it)
            return contentCache[id] != nil ? (idx, id) : nil
        }
        guard indices.count >= Self.maxContentCacheSize else { return }
        let furthest = indices.max(by: { abs($0.0 - currentIndex) < abs($1.0 - currentIndex) })
        guard let (_, id) = furthest else { return }
        (contentCache[id] as? FeedCellTeardownable)?.tearDown()
        contentCache.removeValue(forKey: id)
    }

    func scrollToIndex(_ idx: Int) {
        guard items.indices.contains(idx), collectionView.bounds.height > 0 else { return }
        let offsetY = collectionView.bounds.height * CGFloat(idx)
        collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
        currentIndex = idx
        activeIndexUpdate?(idx)
        refreshVisibleCells()
        updatePrefetchWindow(for: idx)
    }

    func refreshVisibleCells() {
        let indexPaths = collectionView.indexPathsForVisibleItems.sorted { a, b in
            let aActive = isActiveForIndex(a.item)
            let bActive = isActiveForIndex(b.item)
            return !aActive && bActive
        }
        for indexPath in indexPaths {
            guard let cell = collectionView.cellForItem(at: indexPath) as? FeedCell,
                  items.indices.contains(indexPath.item) else { continue }
            let item = items[indexPath.item]
            let isActive = isActiveForIndex(indexPath.item)
            if isActive, case .video(let asset) = item.kind {
                print("[FeedPlayback] refreshVisibleCells: activating index=\(indexPath.item) asset=\(String(asset.localIdentifier.prefix(12)))...")
            }
            cell.setContent(getOrCreateContent(for: item, index: indexPath.item, isActive: isActive))
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.isPagingEnabled = true
        collectionView.isPrefetchingEnabled = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .black
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.register(FeedCell.self, forCellWithReuseIdentifier: FeedCell.reuseId)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize = collectionView.bounds.size
        if !didInitialScroll, items.indices.contains(currentIndex), collectionView.bounds.height > 0 {
            scrollToIndex(currentIndex)
            didInitialScroll = true
            applyScrollSettledState()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let contentH = self.collectionView.contentSize.height
                let boundsH = self.collectionView.bounds.height
                print("[PhotoGroupingScroll] FeedPaged: initialLayout items=\(self.items.count) contentH=\(Int(contentH)) boundsH=\(Int(boundsH))")
            }
        }
    }

    override func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    private func isActiveForIndex(_ index: Int) -> Bool {
        effectiveIsActive?(currentIndex, index) ?? (currentIndex == index)
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedCell.reuseId, for: indexPath) as! FeedCell
        let item = items[indexPath.item]
        let isActive = isActiveForIndex(indexPath.item)
        cell.setContent(getOrCreateContent(for: item, index: indexPath.item, isActive: isActive))
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let feedCell = cell as? FeedCell, items.indices.contains(indexPath.item) else { return }
        let item = items[indexPath.item]
        let isActive = isActiveForIndex(indexPath.item)
        feedCell.setContent(getOrCreateContent(for: item, index: indexPath.item, isActive: isActive))
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let set = IndexSet(indexPaths.map(\.item).sorted())
        let sizePx = CGSize(width: collectionView.bounds.width * UIScreen.main.scale, height: collectionView.bounds.height * UIScreen.main.scale)
        onPrefetch(set, sizePx)
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let set = IndexSet(indexPaths.map(\.item).sorted())
        let sizePx = CGSize(width: collectionView.bounds.width * UIScreen.main.scale, height: collectionView.bounds.height * UIScreen.main.scale)
        onCancelPrefetch(set, sizePx)
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard collectionView.bounds.height > 0 else { return }
        let target = computedPage()
        if target != currentIndex {
            let offsetRatio = scrollView.contentOffset.y / collectionView.bounds.height
            print("[PhotoGroupingScroll] FeedPaged: page \(currentIndex)→\(target) offsetRatio=\(String(format: "%.2f", offsetRatio))")
            currentIndex = target
            onIndexChange(target)
            evictDistantContentIfNeeded(keeping: target)
            refreshVisibleCells()
            updatePrefetchWindow(for: target)
        }
    }

    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        let contentH = scrollView.contentSize.height
        let boundsH = collectionView.bounds.height
        print("[PhotoGroupingScroll] FeedPaged: willBeginDragging items=\(items.count) contentH=\(Int(contentH)) boundsH=\(Int(boundsH))")
    }

    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let offsetY = scrollView.contentOffset.y
        let contentH = scrollView.contentSize.height
        let boundsH = collectionView.bounds.height
        print("[PhotoGroupingScroll] FeedPaged: didEndDecelerating offsetY=\(Int(offsetY)) contentH=\(Int(contentH)) boundsH=\(Int(boundsH)) items=\(items.count)")
        didInitialScroll = true
        applyScrollSettledState()
    }

    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let offsetY = scrollView.contentOffset.y
        let contentH = scrollView.contentSize.height
        print("[PhotoGroupingScroll] FeedPaged: didEndDragging decelerate=\(decelerate) offsetY=\(Int(offsetY)) contentH=\(Int(contentH)) items=\(items.count)")
        if !decelerate {
            didInitialScroll = true
            applyScrollSettledState()
        }
    }

    override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        applyScrollSettledState()
    }

    private func applyScrollSettledState() {
        guard collectionView.bounds.height > 0 else { return }
        let target = computedPage()
        if target != currentIndex {
            currentIndex = target
            onIndexChange(target)
            evictDistantContentIfNeeded(keeping: target)
        }
        print("[FeedPlayback] applyScrollSettledState: currentIndex=\(currentIndex)")
        if items.indices.contains(currentIndex), case .video(let asset) = items[currentIndex].kind {
            VideoStateLog.log(id: asset.localIdentifier, state: "S14_fully_visible")
        }
        activeIndexUpdate?(currentIndex)
        refreshVisibleCells()
        updatePrefetchWindow(for: currentIndex)
    }

    /// Uses 0.55 threshold so we switch when ~55% into new page (avoids flip at exact midpoint).
    private func computedPage() -> Int {
        guard collectionView.bounds.height > 0 else { return currentIndex }
        let page = Int(collectionView.contentOffset.y / collectionView.bounds.height + 0.55)
        return max(0, min(items.count - 1, page))
    }

    private func updatePrefetchWindow(for page: Int) {
        // Base window: 4 behind, 8 ahead (expanded for more buffer)
        var desired = Set((page - 4)...(page + 8)).filter { $0 >= 0 && $0 < items.count }
        // Long videos (>30s): add from extended range so they have more time to load
        for i in (page - 6)...(page + 10) where i >= 0 && i < items.count {
            if case .video(let asset) = items[i].kind, asset.duration > 30 {
                desired.insert(i)
            }
        }
        let adds = desired.subtracting(prefetchedIndices)
        var removes = prefetchedIndices.subtracting(desired)
        // Never cancel current ±1: user may scroll back; keeps active item loading
        let protected = Set([page - 1, page, page + 1].filter { $0 >= 0 && $0 < items.count })
        removes.subtract(protected)
        let sizePx = CGSize(width: collectionView.bounds.width * UIScreen.main.scale, height: collectionView.bounds.height * UIScreen.main.scale)
        // Prioritize current item when unready (TikTok/Instagram pattern)
        if adds.contains(page), !isPageReady(page) {
            onPrefetch(IndexSet([page]), sizePx)
        }
        if !adds.isEmpty { onPrefetch(IndexSet(adds), sizePx) }
        if !removes.isEmpty { onCancelPrefetch(IndexSet(removes), sizePx) }
        prefetchedIndices = desired
    }
}

final class FeedCell: UICollectionViewCell {
    static let reuseId = "FeedCell"
    private var contentViewHost: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setContent(_ view: UIView) {
        if contentViewHost === view { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        contentView.layoutIfNeeded()
        contentViewHost?.removeFromSuperview()
        contentViewHost = view
    }
}
