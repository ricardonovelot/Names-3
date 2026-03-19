//
//  TikTokFeedViewController.swift
//  Names 3
//
//  Pure UIKit implementation of the TikTok-style vertical feed.
//  Uses UICollectionView with paging, TikTokFeedViewModel, and UIKit cell content.
//

import UIKit
import Photos
import AVFoundation
import Combine

@MainActor
final class TikTokFeedViewController: UIViewController, FeedArchitectureProvider {

    var coordinator: CombinedMediaCoordinator?
    var currentFeedItems: [FeedItem] { viewModel.items }

    private var strictUnbindCoordinator: StrictUnbindCoordinator?
    var isFeedVisible: Bool = true {
        didSet {
            if isFeedVisible {
                consumeBridgeIfNeeded()
            }
            pagedController?.setActiveIndexUpdate { [weak self] idx in
                self?.updateCoordinatorCurrentAsset(index: idx)
            }
            refreshVisibleCellsActiveState()
        }
    }

    private let viewModel = TikTokFeedViewModel(mode: .explore)
    private var pagedController: FeedPagedCollectionViewController?
    private var index: Int = 0
    private var didSetInitialIndex = false
    private var readyVideoIDs: Set<String> = []
    private var pendingScrollToAssetID: String?
    private var pendingScrollLoadInFlight = false

    private var carouselCurrentPage: [Int: Int] = [:]
    private var prefetchObserver: NSObjectProtocol?
    private var playbackReadyObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var willResignActiveObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupObservers()
        loadInitialOrBridge()
        viewModel.onAppear()
        viewModel.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyViewModelUpdates() }
            .store(in: &cancellables)
        viewModel.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyViewModelUpdates() }
            .store(in: &cancellables)
        viewModel.$authorization
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyViewModelUpdates() }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        consumeBridgeIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveFeedPosition(index: index)
        viewModel.configureAudioSession(active: false)
    }

    func deactivateAudioSession() {
        viewModel.configureAudioSession(active: false)
    }

    deinit {
        let vm = viewModel
        DispatchQueue.main.async { vm.configureAudioSession(active: false) }
        prefetchObserver.map { NotificationCenter.default.removeObserver($0) }
        playbackReadyObserver.map { NotificationCenter.default.removeObserver($0) }
        backgroundObserver.map { NotificationCenter.default.removeObserver($0) }
        willResignActiveObserver.map { NotificationCenter.default.removeObserver($0) }
        feedSettingsObserver.map { NotificationCenter.default.removeObserver($0) }
    }

    private var feedSettingsObserver: NSObjectProtocol?

    private func setupObservers() {
        prefetchObserver = NotificationCenter.default.addObserver(
            forName: .videoPrefetcherDidCacheAsset, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let id = note.userInfo?["id"] as? String else { return }
            Task { @MainActor in self.readyVideoIDs.insert(id) }
        }
        playbackReadyObserver = NotificationCenter.default.addObserver(
            forName: .videoPlaybackItemReady, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let id = note.userInfo?["id"] as? String else { return }
            Task { @MainActor in self.readyVideoIDs.insert(id) }
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.viewModel.configureAudioSession(active: false)
                self.saveFeedPosition(index: self.index)
            }
        }
        willResignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.viewModel.configureAudioSession(active: false)
            }
        }
        // Save position before ViewModel reloads so we can restore after settings change (e.g. Exclude screenshots)
        feedSettingsObserver = NotificationCenter.default.addObserver(
            forName: .feedSettingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.saveFeedPosition(index: self.index)
            }
        }
    }

    private func loadInitialOrBridge() {
        let bridgeID = coordinator?.consumeBridgeTarget()
        if let id = bridgeID {
            pendingScrollToAssetID = id
            viewModel.initialBridgeAssetID = id
        }
        // viewModel.onAppear will call loadWindowOrBridgeTarget; parent sets bridge from saved position
    }

    /// Injects Carousel assets when switching Carousel→Feed. No fetch—exact same assets.
    func injectFromCarousel(assets: [PHAsset], scrollToAssetID: String?) {
        viewModel.injectItemsFromCarousel(assets, scrollToAssetID: scrollToAssetID)
        if let id = scrollToAssetID {
            didSetInitialIndex = false
            pendingScrollToAssetID = id
        }
        applyViewModelUpdates()
    }

    func scrollToTop() {
        pagedController?.scrollToIndex(0)
    }

    private func consumeBridgeIfNeeded() {
        guard isFeedVisible, let coord = coordinator else { return }
        let bridgeID = coord.consumeBridgeTarget()
        if let id = bridgeID {
            didSetInitialIndex = false
            pendingScrollToAssetID = id
            viewModel.initialBridgeAssetID = id
            applyPendingScrollIfNeeded()
            if viewModel.items.isEmpty || viewModel.indexOfAsset(id: id) == nil {
                pendingScrollLoadInFlight = true
                viewModel.loadWindowContaining(assetID: id)
            } else {
                pendingScrollLoadInFlight = false
            }
        }
    }

    private func buildPagedController() {
        guard pagedController == nil, !viewModel.items.isEmpty else { return }

        let startIndex: Int
        if let pendingID = pendingScrollToAssetID, let idx = viewModel.indexOfAsset(id: pendingID) {
            startIndex = idx
            pendingScrollToAssetID = nil
            pendingScrollLoadInFlight = false
        } else if pendingScrollLoadInFlight, let fallback = viewModel.initialIndexInWindow {
            startIndex = fallback
            pendingScrollToAssetID = nil
            pendingScrollLoadInFlight = false
        } else {
            startIndex = viewModel.initialIndexInWindow ?? 0
        }

        let clamped = max(0, min(viewModel.items.count - 1, startIndex))
        index = clamped
        didSetInitialIndex = true

        let controller = FeedPagedCollectionViewController(
            items: viewModel.items,
            index: clamped,
            idProvider: { $0.id },
            contentBuilder: { [weak self] idx, item, isActive in
                self?.buildContentView(for: item, index: idx, isActive: isActive) ?? UIView()
            },
            onPrefetch: { [weak self] indices, size in self?.handlePrefetch(indices: indices, size: size) },
            onCancelPrefetch: { [weak self] indices, size in self?.handleCancelPrefetch(indices: indices, size: size) },
            isPageReady: { [weak self] idx in self?.pageIsReady(idx) ?? true },
            onIndexChange: { [weak self] newIndex in
                self?.index = newIndex
                self?.updateCoordinatorCurrentAsset(index: newIndex)
                self?.viewModel.loadMoreIfNeeded(currentIndex: newIndex)
                self?.saveFeedPosition(index: newIndex)
            }
        )
        controller.onDeleteItem = { [weak self] idx, item in
            self?.handleDeleteFeedItem(at: idx, item: item)
        }
        controller.carouselCurrentPageProvider = { [weak self] idx in
            self?.carouselCurrentPage[idx] ?? 0
        }
        controller.onDeletePhotoFromCarousel = { [weak self] feedIndex, photoIndex in
            self?.handleDeletePhotoFromCarousel(feedIndex: feedIndex, photoIndex: photoIndex)
        }
        controller.initialIndexOverride = clamped
        controller.effectiveIsActive = { [weak self] curr, idx in
            (curr == idx) && (self?.isFeedVisible ?? false)
        }
        _ = strictUnbindCoordinator ?? {
            let c = StrictUnbindCoordinator()
            strictUnbindCoordinator = c
            return c
        }()
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        pagedController = controller

        updateCoordinatorCurrentAsset(index: index)
    }

    private func buildContentView(for item: FeedItem, index: Int, isActive: Bool) -> UIView {
        switch item.kind {
        case .video(let asset):
            return buildVideoCell(asset: asset, isActive: isActive && isFeedVisible)
        case .photoCarousel(let assets):
            if FeatureFlags.enablePhotoPosts || !assets.isEmpty {
                return MediaFeedCellView(content: .photoCarousel(
                    assets: assets,
                    feedIndex: index,
                    onPageChanged: { [weak self] feedIndex, page in
                        self?.carouselCurrentPage[feedIndex] = page
                    }
                ))
            } else {
                return UIView()
            }
        }
    }

    private func buildVideoCell(asset: PHAsset, isActive: Bool) -> UIView {
        let coord = strictUnbindCoordinator ?? {
            let c = StrictUnbindCoordinator()
            strictUnbindCoordinator = c
            return c
        }()
        return FeedImpl5CellView(asset: asset, isActive: isActive, coordinator: coord)
    }

    private func pageIsReady(_ idx: Int) -> Bool {
        guard viewModel.items.indices.contains(idx) else { return true }
        switch viewModel.items[idx].kind {
        case .video(let a): return readyVideoIDs.contains(a.localIdentifier)
        case .photoCarousel: return true
        }
    }

    private func updateCoordinatorCurrentAsset(index: Int) {
        guard viewModel.items.indices.contains(index) else { return }
        let assetID: String?
        let isVideo: Bool
        switch viewModel.items[index].kind {
        case .video(let a):
            assetID = a.localIdentifier
            isVideo = true
        case .photoCarousel(let arr):
            assetID = arr.first?.localIdentifier
            isVideo = false
        }
        coordinator?.setFocusedAsset(assetID, isVideo: isVideo)
    }

    private func saveFeedPosition(index: Int) {
        guard viewModel.items.indices.contains(index) else { return }
        if let id = FeedDataHelpers.assetID(for: viewModel.items[index]) {
            FeedPositionStore.save(assetID: id)
        }
    }

    private func handleDeleteFeedItem(at idx: Int, item: FeedItem) {
        guard viewModel.items.indices.contains(idx) else { return }
        switch item.kind {
        case .video(let asset):
            let id = asset.localIdentifier
            Task { @MainActor in
                await DeletedVideosStore.shared.hide(id: id)
                await PlaybackPositionStore.shared.clear(id: id)
                VideoPrefetcher.shared.removeCached(for: [id])
            }
        case .photoCarousel:
            break
        }
        viewModel.items.remove(at: idx)
        if index >= viewModel.items.count {
            index = max(0, viewModel.items.count - 1)
        }
        reindexCarouselCurrentPage(afterRemovingAt: idx)
        pagedController?.updateItems(viewModel.items)
        pagedController?.scrollToIndex(index)
    }

    private func handleDeletePhotoFromCarousel(feedIndex: Int, photoIndex: Int) {
        guard viewModel.items.indices.contains(feedIndex) else { return }
        guard case .photoCarousel(var assets) = viewModel.items[feedIndex].kind,
              assets.indices.contains(photoIndex) else { return }
        assets.remove(at: photoIndex)
        if assets.count < 2 {
            viewModel.items.remove(at: feedIndex)
            if index >= viewModel.items.count {
                index = max(0, viewModel.items.count - 1)
            }
            reindexCarouselCurrentPage(afterRemovingAt: feedIndex)
            pagedController?.updateItems(viewModel.items)
            pagedController?.scrollToIndex(index)
        } else {
            viewModel.items[feedIndex] = FeedItem.carousel(assets)
            pagedController?.updateItems(viewModel.items)
            pagedController?.scrollToIndex(feedIndex)
        }
    }

    private func reindexCarouselCurrentPage(afterRemovingAt idx: Int) {
        var next: [Int: Int] = [:]
        for (k, v) in carouselCurrentPage {
            if k < idx { next[k] = v }
            else if k > idx { next[k - 1] = v }
        }
        carouselCurrentPage = next
    }

    func savePositionToStore() {
        saveFeedPosition(index: index)
    }

    func refreshVisibleCellsActiveState() {
        pagedController?.refreshVisibleCells()
    }

    private func handlePrefetch(indices: IndexSet, size: CGSize) {
        guard !viewModel.items.isEmpty else { return }
        let viewportPx = CGSize(width: size.width, height: size.height)
        if let coord = coordinator {
            coord.prefetchForFeed(indices: indices, items: viewModel.items, viewportPx: viewportPx)
        } else {
            fallbackPrefetchForFeed(indices: indices, viewportPx: viewportPx)
        }
    }

    private func handleCancelPrefetch(indices: IndexSet, size: CGSize) {
        guard !viewModel.items.isEmpty else { return }
        let viewportPx = CGSize(width: size.width, height: size.height)
        if let coord = coordinator {
            coord.cancelPrefetchForFeed(indices: indices, items: viewModel.items, viewportPx: viewportPx)
        } else {
            fallbackCancelPrefetchForFeed(indices: indices, viewportPx: viewportPx)
        }
    }

    private func fallbackPrefetchForFeed(indices: IndexSet, viewportPx: CGSize) {
        var videoAssets: [PHAsset] = []
        var photoAssets: [PHAsset] = []
        for i in indices {
            guard viewModel.items.indices.contains(i) else { continue }
            switch viewModel.items[i].kind {
            case .video(let a): videoAssets.append(a)
            case .photoCarousel(let list):
                if FeatureFlags.enablePhotoPosts { photoAssets.append(contentsOf: list) }
            }
        }
        if !videoAssets.isEmpty {
            VideoPrefetcher.shared.prefetch(videoAssets)
            PlayerItemPrefetcher.shared.prefetch(videoAssets)
            if FeedScrollSmoothnessSettings.smoothScrollImprovements {
                ImagePrefetcher.shared.preheatVideoFirstFrames(for: videoAssets)
            }
        }
        if FeatureFlags.enablePhotoPosts, !photoAssets.isEmpty {
            let photoPx = photoTargetSizePx(for: viewportPx)
            ImagePrefetcher.shared.preheat(photoAssets, targetSize: photoPx)
        }
    }

    private func fallbackCancelPrefetchForFeed(indices: IndexSet, viewportPx: CGSize) {
        var videoAssets: [PHAsset] = []
        var photoAssets: [PHAsset] = []
        for i in indices {
            guard viewModel.items.indices.contains(i) else { continue }
            switch viewModel.items[i].kind {
            case .video(let a): videoAssets.append(a)
            case .photoCarousel(let list):
                if FeatureFlags.enablePhotoPosts { photoAssets.append(contentsOf: list) }
            }
        }
        if !videoAssets.isEmpty {
            VideoPrefetcher.shared.cancel(videoAssets)
            PlayerItemPrefetcher.shared.cancel(videoAssets)
        }
        if FeatureFlags.enablePhotoPosts, !photoAssets.isEmpty {
            let photoPx = photoTargetSizePx(for: viewportPx)
            ImagePrefetcher.shared.stopPreheating(photoAssets, targetSize: photoPx)
        }
    }

    private func photoTargetSizePx(for viewportPx: CGSize) -> CGSize {
        let isLandscape = viewportPx.width > viewportPx.height
        let columns: CGFloat = isLandscape ? 4 : 3
        let cell = min(viewportPx.width, viewportPx.height) / columns
        let edge = max(160, min(cell, 512))
        return CGSize(width: edge, height: edge)
    }

    private func applyPendingScrollIfNeeded() {
        guard let id = pendingScrollToAssetID, !viewModel.items.isEmpty,
              let idx = viewModel.indexOfAsset(id: id), idx != index else { return }
        pendingScrollToAssetID = nil
        index = idx
        pagedController?.scrollToIndex(idx)
    }

    func applyViewModelUpdates() {
        if viewModel.authorization == .denied || viewModel.authorization == .restricted {
            return
        }
        if viewModel.isLoading && viewModel.items.isEmpty {
            return
        }
        if viewModel.items.isEmpty {
            return
        }

        if pagedController == nil {
            buildPagedController()
        } else {
            pagedController?.updateItems(viewModel.items)
            if !didSetInitialIndex, !viewModel.items.isEmpty {
                let startIndex: Int
                if let pendingID = pendingScrollToAssetID, let idx = viewModel.indexOfAsset(id: pendingID) {
                    startIndex = idx
                    pendingScrollToAssetID = nil
                    pendingScrollLoadInFlight = false
                } else if pendingScrollLoadInFlight, let fallback = viewModel.initialIndexInWindow {
                    startIndex = fallback
                    pendingScrollToAssetID = nil
                    pendingScrollLoadInFlight = false
                } else {
                    startIndex = viewModel.initialIndexInWindow ?? 0
                }
                let clamped = max(0, min(viewModel.items.count - 1, startIndex))
                index = clamped
                didSetInitialIndex = true
                pagedController?.scrollToIndex(clamped)
            }
            applyPendingScrollIfNeeded()
        }
    }
}
