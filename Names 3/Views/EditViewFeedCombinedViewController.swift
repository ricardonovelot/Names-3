//
//  NameFacesFeedCombinedViewController.swift
//  Names 3
//
//  UIKit container that hosts both Feed (TikTok-style) and Name Faces (carousel) in a single view.
//  Uses Apple's view controller containment pattern. Both children stay mounted for seamless
//  video playback during mode switch. Bridge sync keeps both views on the same asset.
//  Pure UIKit—no SwiftUI.
//

import UIKit
import SwiftData
import Photos
import Combine

// MARK: - NameFacesFeedCombinedViewController

@MainActor
final class NameFacesFeedCombinedViewController: UIViewController {

    enum DisplayMode {
        case feed
        case carousel
    }

    // MARK: - Configuration

    private let modelContext: ModelContext
    private let onDismiss: () -> Void
    private var initialScrollDate: Date?
    private var bottomBarHeight: CGFloat
    private var onDisplayModeChange: ((Bool) -> Void)?  // true = feed mode
    private weak var viewModel: ContentViewModel?

    private let coordinator = CombinedMediaCoordinator()
    private var saveStateCancellable: AnyCancellable?
    private var displayMode: DisplayMode {
        didSet {
            onDisplayModeChange?(displayMode == .feed)
            updateSaveState()
        }
    }

    // MARK: - Child View Controllers

    private var feedViewController: (UIViewController & FeedArchitectureProvider)!
    private var carouselViewController: WelcomeFaceNamingViewController?
    private var carouselLoadingViewController: UIViewController?
    private var carouselAssets: [PHAsset]?
    private var isCarouselLoading = false
    private var isTransitioning = false

    // MARK: - Subviews

    private let feedContainerView = UIView()
    private let carouselContainerView = UIView()
    private var heroMorphImageView: UIImageView?
    private var heroMorphOverlay: UIView?

    private static let windowSize = 500
    private static let bridgeLimit = 80
    private static let bridgeRangeDays = 14
    /// Max asset IDs to persist in carousel cache. Keeps UserDefaults small; 200 is enough for instant open.
    private static let carouselCacheMaxSize = 200

    private var backgroundObserver: NSObjectProtocol?

    // MARK: - Init

    init(
        modelContext: ModelContext,
        onDismiss: @escaping () -> Void,
        initialScrollDate: Date? = nil,
        bottomBarHeight: CGFloat = 0,
        initialDisplayMode: DisplayMode? = nil,
        viewModel: ContentViewModel? = nil
    ) {
        self.modelContext = modelContext
        self.onDismiss = onDismiss
        self.initialScrollDate = initialScrollDate
        self.bottomBarHeight = max(bottomBarHeight, tabBarMinimumHeight)
        self.displayMode = initialDisplayMode ?? (initialScrollDate != nil ? .carousel : .feed)
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    func setOnDisplayModeChange(_ handler: @escaping (Bool) -> Void) {
        onDisplayModeChange = handler
    }

    func setBottomBarHeight(_ height: CGFloat) {
        bottomBarHeight = max(height, tabBarMinimumHeight)
        updateCarouselBottomInset()
        updateFeedBottomInset()
    }

    /// When false (tab switched away), video is paused. Matches TikTok/Instagram behavior.
    func setTabActive(_ active: Bool) {
        guard isTabActive != active else { return }
        isTabActive = active
        if active {
            feedViewController?.isFeedVisible = (displayMode == .feed)
            feedViewController?.refreshVisibleCellsActiveState()
            carouselViewController?.notifyTabBecameActive()
        } else {
            feedViewController?.isFeedVisible = false
            feedViewController?.deactivateAudioSession()
            coordinator.sharedVideoPlayer.setActive(false)
            carouselViewController?.notifyTabBecameInactive()
        }
    }

    private var isTabActive: Bool = true

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupContainers()
        // Restore feed position when reopening app (works for all feed architectures)
        if let savedID = FeedPositionStore.savedAssetID {
            coordinator.setBridgeTarget(savedID)
        }
        setupFeedChild()
        if displayMode == .carousel || initialScrollDate != nil {
            loadCarouselAssetsIfNeeded()
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.feedViewController?.savePositionToStore()
            }
        }
    }

    deinit {
        backgroundObserver.map { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onDisplayModeChange?(displayMode == .feed)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        feedViewController?.savePositionToStore()
    }

    // MARK: - Setup

    private func setupContainers() {
        feedContainerView.translatesAutoresizingMaskIntoConstraints = false
        feedContainerView.backgroundColor = .black
        view.addSubview(feedContainerView)

        carouselContainerView.translatesAutoresizingMaskIntoConstraints = false
        carouselContainerView.backgroundColor = .black
        view.addSubview(carouselContainerView)

        NSLayoutConstraint.activate([
            feedContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            feedContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            feedContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            feedContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            carouselContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            carouselContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            carouselContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            carouselContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupFeedChild() {
        FeedSettingsSnapshot.log()
        let feed = FeedArchitectureMode.current.makeFeedViewController()
        feed.coordinator = coordinator
        feed.isFeedVisible = (displayMode == .feed)
        feed.view.translatesAutoresizingMaskIntoConstraints = false
        feed.view.backgroundColor = .black

        addChild(feed)
        feedContainerView.addSubview(feed.view)
        feed.didMove(toParent: self)

        NSLayoutConstraint.activate([
            feed.view.topAnchor.constraint(equalTo: feedContainerView.topAnchor),
            feed.view.leadingAnchor.constraint(equalTo: feedContainerView.leadingAnchor),
            feed.view.trailingAnchor.constraint(equalTo: feedContainerView.trailingAnchor),
            feed.view.bottomAnchor.constraint(equalTo: feedContainerView.bottomAnchor)
        ])

        feedViewController = feed
        updateFeedBottomInset()
        updateVisibility()
        setupSaveHandlerAndState()
    }

    private func setupSaveHandlerAndState() {
        guard let vm = viewModel else { return }
        vm.photosSaveOrRemoveHandler = { [weak self] in
            self?.performSaveOrRemove()
        }
        updateSaveState()
        saveStateCancellable = coordinator.$currentAssetID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateSaveState()
            }
    }

    private func updateSaveState() {
        guard let vm = viewModel else { return }
        let assets = currentItemAssets()
        let saved = assets.isEmpty ? false : assets.count == 1
            ? AlbumStore.shared.isAssetSaved(assets[0])
            : AlbumStore.shared.isCarouselSaved(assets)
        vm.photosCurrentItemSaved = saved
        vm.photosCurrentItemAssetIDs = assets.map { $0.localIdentifier }
    }

    private func currentItemAssets() -> [PHAsset] {
        if displayMode == .feed, let items = feedViewController?.currentFeedItems, !items.isEmpty {
            let currentID = coordinator.currentAssetID
            let index: Int
            if let id = currentID,
               let idx = items.firstIndex(where: { FeedDataHelpers.itemContainsAsset($0, assetID: id) }) {
                index = idx
            } else {
                index = 0
            }
            return FeedItem.flattenToAssets([items[index]])
        }
        if displayMode == .carousel, let assets = carouselAssets, !assets.isEmpty {
            return assets
        }
        return []
    }

    private func performSaveOrRemove() {
        let assets = currentItemAssets()
        guard !assets.isEmpty else { return }
        let store = AlbumStore.shared
        let isSaved = assets.count == 1 ? store.isAssetSaved(assets[0]) : store.isCarouselSaved(assets)
        if isSaved {
            let alert = UIAlertController(
                title: "Remove from Profile",
                message: "Remove this from your profile?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
                self?.doRemove(assets: assets)
            })
            present(alert, animated: true)
        } else {
            doAdd(assets: assets)
        }
    }

    private func doAdd(assets: [PHAsset]) {
        if assets.count == 1 {
            AlbumStore.shared.addAsset(assets[0])
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            AlbumStore.shared.addAlbumFromAssets(assets, title: "Saved \(formatter.string(from: Date()))")
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        updateSaveState()
    }

    private func doRemove(assets: [PHAsset]) {
        if assets.count == 1 {
            AlbumStore.shared.removeItem(withIdentifier: "asset:\(assets[0].localIdentifier)")
        } else {
            AlbumStore.shared.removeCarousel(assets: assets)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        updateSaveState()
    }

    /// Apply mode requested by SwiftUI (e.g. from the glass bubble). Performs switch when needed.
    func applyRequestedMode(inFeedMode: Bool) {
        let wantFeed = inFeedMode
        let haveFeed = (displayMode == .feed)
        guard wantFeed != haveFeed else { return }
        guard !isTransitioning else { return }

        isTransitioning = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
        let goingToCarousel = !wantFeed
        let assetID = coordinator.currentAssetID
        if let id = assetID { coordinator.setBridgeTarget(id) }

        Task { @MainActor in
            if let id = assetID, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                let size = CGSize(width: 1200, height: 1200)
                let heroImage = await ImagePrefetcher.shared.requestImage(for: asset, targetSize: size)
                await MainActor.run {
                    performMorphTransition(heroImage: heroImage, goingToCarousel: goingToCarousel)
                }
            } else {
                performModeSwitch(goingToCarousel: goingToCarousel)
            }
        }
    }

    // MARK: - Carousel Loading

    private func loadCarouselAssetsIfNeeded() {
        guard !isCarouselLoading else { return }
        let bridgeID = coordinator.consumeBridgeTarget()

        // Feed→Carousel: use Feed's assets directly—no fetch, exact same data
        if displayMode == .feed, let feedItems = feedViewController?.currentFeedItems, !feedItems.isEmpty {
            let assets = FeedItem.flattenToAssets(feedItems)
            guard !assets.isEmpty else {
                fallbackLoadCarouselAssets(bridgeID: bridgeID)
                return
            }
            carouselAssets = assets
            updateSaveState()
            ensureCarouselChild(bridgeID: bridgeID)
            return
        }

        guard carouselAssets == nil else {
            ensureCarouselChild(bridgeID: bridgeID)
            return
        }

        fallbackLoadCarouselAssets(bridgeID: bridgeID)
    }

    private func fallbackLoadCarouselAssets(bridgeID: String?) {
        guard !isCarouselLoading else { return }
        isCarouselLoading = true
        showCarouselLoading()

        Task {
            let isLowStorage = await MainActor.run { StorageMonitor.shared.isLowOnDeviceStorage }
            _ = await PhotoLibraryService.shared.requestAuthorization()
            let assets: [PHAsset]

            if let id = bridgeID, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                let (windowAssets, _) = await NameFacesCarouselAssetFetcher.fetchMixedAssetsAround(
                    targetAsset: asset, rangeDays: Self.bridgeRangeDays, limit: Self.bridgeLimit
                )
                assets = Self.filterHiddenVideos(windowAssets.isEmpty
                    ? await NameFacesCarouselAssetFetcher.fetchInitialAssets(limit: Self.windowSize)
                    : windowAssets)
            } else if !isLowStorage, let cached = Self.loadCarouselAssetsFromCache(limit: Self.windowSize) {
                assets = Self.filterHiddenVideos(cached)
            } else {
                let raw = await NameFacesCarouselAssetFetcher.fetchInitialAssets(limit: Self.windowSize)
                assets = Self.filterHiddenVideos(raw)
                if !assets.isEmpty, !isLowStorage {
                    Self.saveCarouselCache(assetIDs: assets.map { $0.localIdentifier })
                }
            }

            await MainActor.run {
                self.carouselAssets = assets
                self.isCarouselLoading = false
                self.hideCarouselLoading()
                self.updateSaveState()
                self.ensureCarouselChild(bridgeID: bridgeID)
            }
        }
    }

    private static func filterHiddenVideos(_ assets: [PHAsset]) -> [PHAsset] {
        let hidden = DeletedVideosStore.snapshot()
        guard !hidden.isEmpty else { return assets }
        return assets.filter { $0.mediaType != .video || !hidden.contains($0.localIdentifier) }
    }

    private static func loadCarouselAssetsFromCache(limit: Int) -> [PHAsset]? {
        guard !UserDefaults.standard.bool(forKey: WelcomeFaceNamingViewController.cacheInvalidatedKey) else {
            return nil
        }
        guard let ids = UserDefaults.standard.stringArray(forKey: WelcomeFaceNamingViewController.cachedCarouselAssetIDsKey),
              !ids.isEmpty else { return nil }
        let idsToResolve = Array(ids.prefix(limit))
        let result = PHAsset.fetchAssets(withLocalIdentifiers: idsToResolve, options: nil)
        var byId: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in byId[asset.localIdentifier] = asset }
        var ordered: [PHAsset] = []
        for id in idsToResolve {
            if let asset = byId[id] { ordered.append(asset) }
        }
        guard ordered.count == idsToResolve.count else { return nil }
        return ordered
    }

    private static func saveCarouselCache(assetIDs: [String]) {
        let trimmed = Array(assetIDs.prefix(carouselCacheMaxSize))
        UserDefaults.standard.set(trimmed, forKey: WelcomeFaceNamingViewController.cachedCarouselAssetIDsKey)
        UserDefaults.standard.set(false, forKey: WelcomeFaceNamingViewController.cacheInvalidatedKey)
    }

    private func showCarouselLoading() {
        let loading = UIViewController()
        loading.view.backgroundColor = .black
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        loading.view.addSubview(spinner)
        let label = UILabel()
        label.text = "Loading photos…"
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        loading.view.addSubview(label)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: loading.view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: loading.view.centerYAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            label.centerXAnchor.constraint(equalTo: loading.view.centerXAnchor)
        ])

        addChild(loading)
        loading.view.translatesAutoresizingMaskIntoConstraints = false
        carouselContainerView.addSubview(loading.view)
        NSLayoutConstraint.activate([
            loading.view.topAnchor.constraint(equalTo: carouselContainerView.topAnchor),
            loading.view.leadingAnchor.constraint(equalTo: carouselContainerView.leadingAnchor),
            loading.view.trailingAnchor.constraint(equalTo: carouselContainerView.trailingAnchor),
            loading.view.bottomAnchor.constraint(equalTo: carouselContainerView.bottomAnchor)
        ])
        loading.didMove(toParent: self)
        carouselLoadingViewController = loading
    }

    private func hideCarouselLoading() {
        guard let loading = carouselLoadingViewController else { return }
        loading.willMove(toParent: nil)
        loading.view.removeFromSuperview()
        loading.removeFromParent()
        carouselLoadingViewController = nil
    }

    private func ensureCarouselChild(bridgeID: String? = nil) {
        guard let assets = carouselAssets, !assets.isEmpty else { return }

        if let carousel = carouselViewController {
            carousel.replacePrioritizedAssetsForModeSwitch(assets, scrollToAssetID: bridgeID)
            updateCarouselBottomInset()
            updateVisibility()
            return
        }

        let carousel = WelcomeFaceNamingViewController(
            prioritizedAssets: assets,
            modelContext: modelContext,
            initialScrollDate: initialScrollDate,
            initialAssetID: bridgeID,
            useQuickInputForName: true,
            coordinator: coordinator
        )
        carousel.delegate = self
        carousel.onPrioritizedAssetsDidChange = { [weak self] newAssets in
            self?.carouselAssets = newAssets
        }
        carousel.onCurrentAssetDidChange = { [weak self] id, isVideo in
            Task { @MainActor in
                self?.coordinator.setFocusedAsset(id, isVideo: isVideo)
            }
        }

        addChild(carousel)
        carousel.view.translatesAutoresizingMaskIntoConstraints = false
        carouselContainerView.addSubview(carousel.view)
        NSLayoutConstraint.activate([
            carousel.view.topAnchor.constraint(equalTo: carouselContainerView.topAnchor),
            carousel.view.leadingAnchor.constraint(equalTo: carouselContainerView.leadingAnchor),
            carousel.view.trailingAnchor.constraint(equalTo: carouselContainerView.trailingAnchor),
            carousel.view.bottomAnchor.constraint(equalTo: carouselContainerView.bottomAnchor)
        ])
        carousel.didMove(toParent: self)
        carouselViewController = carousel

        if let id = bridgeID {
            carousel.scrollToAssetIDIfNeeded(id)
        }
        updateCarouselBottomInset()
        updateVisibility()
    }

    private func updateCarouselBottomInset() {
        guard let carousel = carouselViewController else { return }
        carousel.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomBarHeight, right: 0)
    }

    private func updateFeedBottomInset() {
        feedViewController?.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomBarHeight, right: 0)
    }

    // MARK: - Visibility

    private func updateVisibility() {
        let isFeed = displayMode == .feed
        feedViewController?.isFeedVisible = isFeed
        feedContainerView.alpha = isFeed ? 1 : 0
        feedContainerView.isUserInteractionEnabled = isFeed
        carouselContainerView.alpha = isFeed ? 0 : 1
        carouselContainerView.isUserInteractionEnabled = !isFeed
        carouselViewController?.notifyCarouselBecameVisible(!isFeed)
    }

    // MARK: - Mode Switch (Hero Morph when available)

    private func performMorphTransition(heroImage: UIImage?, goingToCarousel: Bool) {
        guard let image = heroImage else {
            performModeSwitch(goingToCarousel: goingToCarousel)
            return
        }

        let overlay = UIView()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        heroMorphOverlay = overlay

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.cornerRadius = goingToCarousel ? 0 : 16
        imageView.layer.cornerCurve = .continuous
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOpacity = 0.4
        imageView.layer.shadowRadius = 20
        imageView.layer.shadowOffset = CGSize(width: 0, height: 10)
        overlay.addSubview(imageView)
        heroMorphImageView = imageView

        let w = view.bounds.width
        let h = view.bounds.height
        let fullFrame = CGRect(x: 0, y: 0, width: w, height: h)
        let smallFrame = CGRect(x: w * 0.1, y: h * 0.15, width: w * 0.8, height: h * 0.5)

        let initialFrame: CGRect
        let targetFrame: CGRect
        let targetCornerRadius: CGFloat
        if goingToCarousel {
            initialFrame = fullFrame
            targetFrame = smallFrame
            targetCornerRadius = 16
        } else {
            initialFrame = smallFrame
            targetFrame = fullFrame
            targetCornerRadius = 0
        }
        imageView.frame = initialFrame
        imageView.layer.cornerRadius = goingToCarousel ? 0 : 16

        view.layoutIfNeeded()

        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0
        ) {
            imageView.frame = targetFrame
            imageView.layer.cornerRadius = targetCornerRadius
        } completion: { [weak self] _ in
            guard let self else { return }
            if goingToCarousel {
                self.loadCarouselAssetsIfNeeded()
                self.displayMode = .carousel
            } else {
                let bridgeID = self.coordinator.consumeBridgeTarget()
                if let carousel = self.carouselViewController {
                    self.feedViewController.injectFromCarousel(assets: carousel.currentPrioritizedAssets, scrollToAssetID: bridgeID)
                }
                self.displayMode = .feed
            }
            self.updateVisibility()
            self.view.layoutIfNeeded()
            self.isTransitioning = false

            UIView.animate(withDuration: 0.15) {
                self.heroMorphOverlay?.alpha = 0
            } completion: { _ in
                self.heroMorphOverlay?.removeFromSuperview()
                self.heroMorphOverlay = nil
                self.heroMorphImageView = nil
            }
        }
    }

    private func performModeSwitch(goingToCarousel: Bool) {
        if goingToCarousel {
            displayMode = .carousel
            loadCarouselAssetsIfNeeded()
        } else {
            let bridgeID = coordinator.consumeBridgeTarget()
            if let carousel = carouselViewController {
                feedViewController.injectFromCarousel(assets: carousel.currentPrioritizedAssets, scrollToAssetID: bridgeID)
            }
            displayMode = .feed
        }
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut]) {
            self.updateVisibility()
        } completion: { _ in
            self.isTransitioning = false
        }
    }
}

// MARK: - WelcomeFaceNamingViewControllerDelegate

extension NameFacesFeedCombinedViewController: WelcomeFaceNamingViewControllerDelegate {
    func welcomeFaceNamingViewControllerDidFinish(_ controller: WelcomeFaceNamingViewController) {
        onDismiss()
    }
}
