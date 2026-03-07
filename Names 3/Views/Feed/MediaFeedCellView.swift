//
//  MediaFeedCellView.swift
//  Names 3
//
//  Unified UIKit feed cell for video and photo carousel. Uses PlayerLayerView/SingleAssetPlayer
//  for video and UICollectionView with horizontal paging for photos—standard Apple patterns.
//

import UIKit
import AVFoundation
import Photos

private enum MediaFeedConstants {
    static let horizontalPadding: CGFloat = 16
    static let maxHeightFraction: CGFloat = 0.7
}

final class MediaFeedCellView: UIView, FeedCellContentUpdatable, FeedCellTeardownable {

    enum Content {
        case video(asset: PHAsset, isActive: Bool, sharedPlayer: SingleAssetPlayer?)
        case photoCarousel([PHAsset])
    }

    private let contentView: MediaContentContentView

    init(content: Content) {
        self.contentView = MediaContentContentView(content: content)
        super.init(frame: .zero)
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - FeedCellContentUpdatable

    func updateIsActive(_ active: Bool) {
        print("[FeedPlayback] MediaFeedCellView.updateIsActive(\(active))")
        contentView.setActive(active)
    }

    // MARK: - Setup

    private func setupContent() {
        backgroundColor = .black
        addAndPin(contentView)
    }

    private func addAndPin(_ subview: UIView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subview)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: trailingAnchor),
            subview.topAnchor.constraint(equalTo: topAnchor),
            subview.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Call when content is evicted from cache (item removed from feed). Do not tear down when
    /// moving between cells—that causes blinking when scrolling back to cached content.
    func tearDown() {
        contentView.tearDown()
    }
}

// MARK: - Media Content (Video + Photo Carousel)

private final class MediaContentContentView: UIView {

    private enum Mode {
        case video(asset: PHAsset, isActive: Bool, sharedPlayer: SingleAssetPlayer?)
        case photoCarousel([PHAsset])
    }

    private let mode: Mode

    // Video
    private var videoAsset: PHAsset?
    private var isActive: Bool = false
    private var sharedPlayer: SingleAssetPlayer?
    private let ownPlayer = SingleAssetPlayer()
    /// When we have sharedPlayer: use ownPlayer when inactive (so we show our video, not the shared one).
    /// When active, use sharedPlayer. When no sharedPlayer, always use ownPlayer.
    private var effectivePlayer: SingleAssetPlayer {
        if let shared = sharedPlayer {
            return isActive ? shared : ownPlayer
        }
        return ownPlayer
    }
    private let playerLayerView = PlayerLayerView()
    private let firstFrameOverlay = UIImageView()
    private var firstFrameLoadTask: Task<Void, Never>?
    private var firstFrameTimeoutTask: Task<Void, Never>?
    private var layerReadyObserver: NSKeyValueObservation?

    // Photo carousel (driver-based for strategies 2–5)
    private var photoAssets: [PHAsset]?
    private var carouselDriver: PhotoCarouselDriver?
    private var collectionView: UICollectionView?
    private var pageControl: UIPageControl?
    private var layout: UICollectionViewFlowLayout?
    private var loadTaskCancellables: [IndexPath: Task<Void, Never>] = [:]
    private var hasTriggeredCarouselPreheat = false

    init(content: MediaFeedCellView.Content) {
        switch content {
        case .video(let asset, let isActive, let sharedPlayer):
            self.mode = .video(asset: asset, isActive: isActive, sharedPlayer: sharedPlayer)
        case .photoCarousel(let assets):
            self.mode = .photoCarousel(assets)
        }
        super.init(frame: .zero)
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setActive(_ active: Bool) {
        guard let asset = videoAsset else { return }
        guard isActive != active else { return }
        print("[FeedPlayback] MediaContentContentView.setActive(\(active)) asset=\(String(asset.localIdentifier.prefix(12)))... shared=\(sharedPlayer != nil)")
        isActive = active
        if let shared = sharedPlayer {
            if active {
                VideoStateLog.log(id: asset.localIdentifier, state: "S10_cell_active")
                shared.setAsset(asset)
                shared.setActive(true)
                ownPlayer.cancel()
                bindPlayerLayerToEffectivePlayer()
            } else {
                shared.setActive(false)
                ownPlayer.setAsset(asset)
                ownPlayer.setActive(false)
                bindPlayerLayerToEffectivePlayer()
            }
        } else {
            if active {
                VideoStateLog.log(id: asset.localIdentifier, state: "S10_cell_active")
                ownPlayer.setAsset(asset)
                ownPlayer.setActive(true)
            } else {
                ownPlayer.setActive(false)
            }
            bindPlayerLayerToEffectivePlayer()
        }
    }

    private func bindPlayerLayerToEffectivePlayer() {
        let player = effectivePlayer.player
        if playerLayerView.playerLayer.player !== player, let asset = videoAsset {
            VideoStateLog.log(id: asset.localIdentifier, state: "S11_layer_bound")
            playerLayerView.playerLayer.player = nil
            playerLayerView.playerLayer.player = player
        }
        playerLayerView.setNeedsLayout()
        playerLayerView.layoutIfNeeded()
    }

    func tearDown() {
        if videoAsset != nil {
            layerReadyObserver?.invalidate()
            layerReadyObserver = nil
            firstFrameTimeoutTask?.cancel()
            firstFrameTimeoutTask = nil
            firstFrameLoadTask?.cancel()
            firstFrameLoadTask = nil
            firstFrameOverlay.removeFromSuperview()
            if sharedPlayer != nil {
                sharedPlayer?.setActive(false)
                ownPlayer.cancel()
            } else {
                ownPlayer.cancel()
            }
        } else {
            carouselDriver?.onCarouselDisappeared()
            loadTaskCancellables.values.forEach { $0.cancel() }
            loadTaskCancellables.removeAll()
        }
    }

    private func setupContent() {
        backgroundColor = .black
        switch mode {
        case .video(let asset, let active, let shared):
            videoAsset = asset
            isActive = active
            sharedPlayer = shared
            setupVideo()
            configurePlayback()
        case .photoCarousel(let assets):
            photoAssets = assets
            setupPhotoCarousel()
        }
    }

    // MARK: - Video

    private func setupVideo() {
        guard let asset = videoAsset else { return }
        playerLayerView.backgroundColor = .black
        playerLayerView.playerLayer.videoGravity = .resizeAspectFill
        bindPlayerLayerToEffectivePlayer()
        addSubview(playerLayerView)
        playerLayerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerLayerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerLayerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerLayerView.topAnchor.constraint(equalTo: topAnchor),
            playerLayerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        firstFrameOverlay.contentMode = .scaleAspectFill
        firstFrameOverlay.clipsToBounds = true
        firstFrameOverlay.backgroundColor = .black
        firstFrameOverlay.alpha = 0
        addSubview(firstFrameOverlay)
        firstFrameOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            firstFrameOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            firstFrameOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            firstFrameOverlay.topAnchor.constraint(equalTo: topAnchor),
            firstFrameOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        loadFirstFrameOverlay(for: asset)
        layerReadyObserver = playerLayerView.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard let self else { return }
            guard layer.isReadyForDisplay else { return }
            if let asset = self.videoAsset {
                VideoStateLog.log(id: asset.localIdentifier, state: "S12_layer_ready")
            }
            DispatchQueue.main.async { [weak self] in
                self?.hideFirstFrameOverlay()
            }
        }
        firstFrameTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            if firstFrameOverlay.superview != nil { hideFirstFrameOverlay() }
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleVideoTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    private func loadFirstFrameOverlay(for asset: PHAsset) {
        let size: CGSize = StorageMonitor.shared.isLowOnDeviceStorage
            ? CGSize(width: 480, height: 480)
            : CGSize(width: 800, height: 800)
        firstFrameLoadTask = Task { @MainActor in
            let image = await ImagePrefetcher.shared.requestVideoFirstFrame(for: asset, targetSize: size)
            guard !Task.isCancelled else { return }
            firstFrameOverlay.image = image
            UIView.animate(withDuration: 0.12) { self.firstFrameOverlay.alpha = 1 }
        }
    }

    private func hideFirstFrameOverlay() {
        guard firstFrameOverlay.superview != nil else { return }
        if let asset = videoAsset {
            VideoStateLog.log(id: asset.localIdentifier, state: "S13_overlay_hidden")
        }
        layerReadyObserver?.invalidate()
        layerReadyObserver = nil
        firstFrameTimeoutTask?.cancel()
        firstFrameTimeoutTask = nil
        firstFrameLoadTask?.cancel()
        firstFrameLoadTask = nil
        UIView.animate(withDuration: 0.06) {
            self.firstFrameOverlay.alpha = 0
        } completion: { _ in
            self.firstFrameOverlay.removeFromSuperview()
        }
    }

    private func configurePlayback() {
        guard case .video(let asset, let active, let shared) = mode else { return }
        if let shared = shared {
            if active {
                shared.setAsset(asset)
                shared.setActive(true)
            } else {
                ownPlayer.setAsset(asset)
                ownPlayer.setActive(false)
            }
        } else {
            ownPlayer.setAsset(asset)
            ownPlayer.setActive(active)
        }
    }

    @objc private func handleVideoTap() {
        guard isActive, case .video = mode else { return }
        effectivePlayer.togglePlay()
    }

    // MARK: - Photo Carousel

    private func setupPhotoCarousel() {
        guard let assets = photoAssets else { return }
        carouselDriver = PhotoArchitectureMode.current.makeDriver()

        let layout = UICollectionViewFlowLayout()
        self.layout = layout
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView = cv
        cv.backgroundColor = .black
        cv.isPagingEnabled = true
        cv.showsHorizontalScrollIndicator = false
        cv.delegate = self
        cv.dataSource = self
        cv.prefetchDataSource = self
        cv.isPrefetchingEnabled = true
        cv.register(PhotoCarouselPageCell.self, forCellWithReuseIdentifier: PhotoCarouselPageCell.reuseId)
        cv.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cv)

        let pc = UIPageControl()
        self.pageControl = pc
        pc.numberOfPages = max(1, assets.count)
        pc.currentPage = 0
        pc.currentPageIndicatorTintColor = .white
        pc.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.35)
        pc.translatesAutoresizingMaskIntoConstraints = false
        pc.isHidden = assets.count <= 1
        addSubview(pc)

        NSLayoutConstraint.activate([
            cv.leadingAnchor.constraint(equalTo: leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: trailingAnchor),
            cv.topAnchor.constraint(equalTo: topAnchor),
            cv.bottomAnchor.constraint(equalTo: bottomAnchor),
            pc.centerXAnchor.constraint(equalTo: centerXAnchor),
            pc.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -28)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let layout = layout else { return }
        layout.itemSize = bounds.size

        if !hasTriggeredCarouselPreheat, let assets = photoAssets, let driver = carouselDriver {
            hasTriggeredCarouselPreheat = true
            let scale = UIScreen.main.scale
            let viewportPx = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            driver.onCarouselAppeared(assets: assets, viewportSize: viewportPx)
        }
    }

    private func loadImage(for cell: PhotoCarouselPageCell, at indexPath: IndexPath) {
        guard let assets = photoAssets, assets.indices.contains(indexPath.item) else { return }
        let asset = assets[indexPath.item]
        let assetID = asset.localIdentifier
        loadTaskCancellables[indexPath]?.cancel()
        cell.cancelPendingLoad()
        cell.setExpectedAssetID(assetID)
        cell.setDimensionsOverlay(w: asset.pixelWidth, h: asset.pixelHeight)
        cell.setLoadingPlaceholderVisible(true)
        let scale = UIScreen.main.scale
        let w = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let h = bounds.height > 0 ? bounds.height : UIScreen.main.bounds.height
        var targetSize = CGSize(
            width: min(max(1, w) - MediaFeedConstants.horizontalPadding * 2, CGFloat(asset.pixelWidth)) * scale,
            height: min(max(1, h) * MediaFeedConstants.maxHeightFraction, CGFloat(asset.pixelHeight)) * scale
        )
        if StorageMonitor.shared.isLowOnDeviceStorage {
            targetSize = CGSize(width: targetSize.width * 0.6, height: targetSize.height * 0.6)
        }
        guard targetSize.width > 0, targetSize.height > 0 else { return }

        let task = Task { @MainActor in
            let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
            if let cached = ImageCacheService.shared.image(for: cacheKey) {
                cell.applyImageIfMatching(cached, assetID: assetID)
                return
            }
            for await (image, isDegraded) in ImagePrefetcher.shared.progressiveImage(for: asset, targetSize: targetSize) {
                guard !Task.isCancelled else { return }
                let decoded = await ImageDecodingService.decodeForDisplay(image)
                guard !Task.isCancelled else { return }
                cell.applyImageIfMatching(decoded, assetID: assetID)
                if !isDegraded {
                    if let decoded { ImageCacheService.shared.setImage(decoded, for: cacheKey) }
                    break
                }
            }
        }
        loadTaskCancellables[indexPath] = task
        cell.setLoadTask(task)
    }

    private func cancelLoad(for indexPath: IndexPath) {
        loadTaskCancellables[indexPath]?.cancel()
        loadTaskCancellables.removeValue(forKey: indexPath)
    }
}

extension MediaContentContentView: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        photoAssets?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoCarouselPageCell.reuseId, for: indexPath) as! PhotoCarouselPageCell
        loadImage(for: cell, at: indexPath)
        return cell
    }
}

extension MediaContentContentView: UICollectionViewDataSourcePrefetching {

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let assets = photoAssets, let driver = carouselDriver else { return }
        let page = Int(round(collectionView.contentOffset.x / collectionView.bounds.width))
        let indices = driver.prefetchIndices(currentPage: page, totalCount: assets.count)
        for indexPath in indexPaths.prefix(6) {
            guard indices.contains(indexPath.item), assets.indices.contains(indexPath.item) else { continue }
            preloadImage(at: indexPath.item)
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for indexPath in indexPaths {
            carouselDriver?.cancelLoad(at: indexPath.item)
            cancelLoad(for: indexPath)
        }
    }

    private func preloadImage(at index: Int) {
        guard let assets = photoAssets, assets.indices.contains(index) else { return }
        let asset = assets[index]
        let scale = UIScreen.main.scale
        let w = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let h = bounds.height > 0 ? bounds.height : UIScreen.main.bounds.height
        var targetSize = CGSize(
            width: min(max(1, w) - MediaFeedConstants.horizontalPadding * 2, CGFloat(asset.pixelWidth)) * scale,
            height: min(max(1, h) * MediaFeedConstants.maxHeightFraction, CGFloat(asset.pixelHeight)) * scale
        )
        if StorageMonitor.shared.isLowOnDeviceStorage {
            targetSize = CGSize(width: targetSize.width * 0.6, height: targetSize.height * 0.6)
        }
        guard targetSize.width > 0, targetSize.height > 0 else { return }
        ImagePrefetcher.shared.preheat([asset], targetSize: targetSize)
        Task { @MainActor in
            let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
            guard ImageCacheService.shared.image(for: cacheKey) == nil else { return }
            let image = await ImagePrefetcher.shared.requestImage(for: asset, targetSize: targetSize)
            if let image {
                let decoded = await ImageDecodingService.decodeForDisplay(image)
                if let decoded {
                    ImageCacheService.shared.setImage(decoded, for: cacheKey)
                }
            }
        }
    }
}

extension MediaContentContentView: UICollectionViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard bounds.width > 0, let assets = photoAssets else { return }
        let page = Int(round(scrollView.contentOffset.x / bounds.width))
        pageControl?.currentPage = min(max(0, page), assets.count - 1)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        print("[PhotoGroupingScroll] MediaFeedCellView: carousel willBeginDragging (horizontal)")
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        cancelLoad(for: indexPath)
    }
}

// MARK: - PhotoCarouselPageCell

private final class PhotoCarouselPageCell: UICollectionViewCell {

    static let reuseId = "PhotoCarouselPageCell"

    private let imageView: UIImageView = {
        let v = UIImageView()
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // Solution 3: Loading placeholder instead of black
    private let loadingOverlay: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let v = UIActivityIndicatorView(style: .medium)
        v.color = .white
        v.hidesWhenStopped = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let dimensionLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        l.textColor = .white
        l.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        l.layer.cornerRadius = 8
        l.layer.masksToBounds = true
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    private var expectedAssetID: String?
    private var loadTask: Task<Void, Never>?
    private var showLoadingPlaceholder = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        contentView.addSubview(imageView)
        contentView.addSubview(loadingOverlay)
        contentView.addSubview(dimensionLabel)
        loadingOverlay.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: MediaFeedConstants.horizontalPadding),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -MediaFeedConstants.horizontalPadding),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: MediaFeedConstants.maxHeightFraction),
            loadingOverlay.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            loadingOverlay.topAnchor.constraint(equalTo: imageView.topAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            activityIndicator.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor),
            dimensionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dimensionLabel.bottomAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.bottomAnchor, constant: -40)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDimensionsOverlay(w: Int, h: Int) {
        let show = ExcludeScreenshotsPreference.showDimensionOverlay
        dimensionLabel.isHidden = !show
        if show {
            let dims = "\(w)×\(h)"
            let device = ExcludeScreenshotsPreference.deviceName(forWidth: w, height: h)
            dimensionLabel.text = device.map { "\(dims) · \($0)" } ?? dims
        }
    }

    func setExpectedAssetID(_ assetID: String) {
        expectedAssetID = assetID
    }

    func setLoadTask(_ task: Task<Void, Never>) {
        loadTask = task
    }

    func setLoadingPlaceholderVisible(_ visible: Bool) {
        showLoadingPlaceholder = visible
        if visible, imageView.image == nil {
            loadingOverlay.isHidden = false
            activityIndicator.startAnimating()
        }
    }

    func cancelPendingLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    func applyImageIfMatching(_ image: UIImage?, assetID: String) {
        guard expectedAssetID == assetID else { return }
        guard let image else { return }
        imageView.image = image
        imageView.alpha = 1
        loadingOverlay.isHidden = true
        activityIndicator.stopAnimating()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelPendingLoad()
        imageView.image = nil
        imageView.alpha = 1
        loadingOverlay.isHidden = true
        activityIndicator.stopAnimating()
        expectedAssetID = nil
    }
}
