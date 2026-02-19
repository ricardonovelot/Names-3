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
            contentCache = contentCache.filter { key, _ in newItems.contains { idProvider($0) == key } }
            collectionView.reloadData()
            prefetchedIndices = []
        }
    }

    private func getOrCreateContent(for item: FeedItem, index: Int, isActive: Bool) -> UIView {
        let id = idProvider(item)
        if let cached = contentCache[id] {
            if let updatable = cached as? FeedCellContentUpdatable {
                updatable.updateIsActive(isActive)
            }
            return cached
        }
        let view = contentBuilder(index, item, isActive)
        contentCache[id] = view
        return view
    }

    func scrollToIndex(_ idx: Int) {
        guard items.indices.contains(idx), collectionView.bounds.height > 0 else { return }
        let offsetY = collectionView.bounds.height * CGFloat(idx)
        collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
        currentIndex = idx
        refreshVisibleCells()
        updatePrefetchWindow(for: idx)
    }

    func refreshVisibleCells() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let cell = collectionView.cellForItem(at: indexPath) as? FeedCell,
                  items.indices.contains(indexPath.item) else { continue }
            let item = items[indexPath.item]
            let isActive = effectiveIsActive?(currentIndex, indexPath.item) ?? (currentIndex == indexPath.item)
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
        }
    }

    override func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedCell.reuseId, for: indexPath) as! FeedCell
        let item = items[indexPath.item]
        let isActive = effectiveIsActive?(currentIndex, indexPath.item) ?? (currentIndex == indexPath.item)
        cell.setContent(getOrCreateContent(for: item, index: indexPath.item, isActive: isActive))
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let feedCell = cell as? FeedCell, items.indices.contains(indexPath.item) else { return }
        let item = items[indexPath.item]
        let isActive = effectiveIsActive?(currentIndex, indexPath.item) ?? (currentIndex == indexPath.item)
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
            currentIndex = target
            onIndexChange(target)
            activeIndexUpdate?(target)
            refreshVisibleCells()
            updatePrefetchWindow(for: target)
        }
    }

    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        didInitialScroll = true
    }

    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { didInitialScroll = true }
    }

    private func computedPage() -> Int {
        guard collectionView.bounds.height > 0 else { return currentIndex }
        let page = Int(round(collectionView.contentOffset.y / collectionView.bounds.height))
        return max(0, min(items.count - 1, page))
    }

    private func updatePrefetchWindow(for page: Int) {
        let desired = Set([page - 1, page, page + 1, page + 2, page + 3].filter { $0 >= 0 && $0 < items.count })
        let adds = desired.subtracting(prefetchedIndices)
        let removes = prefetchedIndices.subtracting(desired)
        let sizePx = CGSize(width: collectionView.bounds.width * UIScreen.main.scale, height: collectionView.bounds.height * UIScreen.main.scale)
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
        contentViewHost?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        contentViewHost = view
    }
}
