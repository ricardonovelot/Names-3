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

    private var prefetchObserver: NSObjectProtocol?
    private var playbackReadyObserver: NSObjectProtocol?
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

    deinit {
        let vm = viewModel
        DispatchQueue.main.async { vm.configureAudioSession(active: false) }
        prefetchObserver.map { NotificationCenter.default.removeObserver($0) }
        playbackReadyObserver.map { NotificationCenter.default.removeObserver($0) }
    }

    private func setupObservers() {
        prefetchObserver = NotificationCenter.default.addObserver(
            forName: .videoPrefetcherDidCacheAsset, object: nil, queue: .main
        ) { [weak self] note in
            if let id = note.userInfo?["id"] as? String {
                self?.readyVideoIDs.insert(id)
            }
        }
        playbackReadyObserver = NotificationCenter.default.addObserver(
            forName: .videoPlaybackItemReady, object: nil, queue: .main
        ) { [weak self] note in
            if let id = note.userInfo?["id"] as? String {
                self?.readyVideoIDs.insert(id)
            }
        }
    }

    private func loadInitialOrBridge() {
        let bridgeID = coordinator?.consumeBridgeTarget()
        if let id = bridgeID {
            pendingScrollToAssetID = id
            viewModel.initialBridgeAssetID = id
        }
        // viewModel.onAppear will call loadWindowOrBridgeTarget which uses initialBridgeAssetID
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
            }
        )
        controller.initialIndexOverride = clamped
        controller.effectiveIsActive = { [weak self] curr, idx in
            (curr == idx) && (self?.isFeedVisible ?? false)
        }
        let coord = strictUnbindCoordinator ?? {
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
                return MediaFeedCellView(content: .photoCarousel(assets))
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
