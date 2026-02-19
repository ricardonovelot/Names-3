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

final class MediaFeedCellView: UIView, FeedCellContentUpdatable {

    enum Content {
        case video(asset: PHAsset, isActive: Bool, sharedPlayer: SingleAssetPlayer?)
        case photoCarousel([PHAsset])
    }

    private let content: Content
    private var videoView: VideoContentView?
    private var photoView: PhotoCarouselContentView?

    init(content: Content) {
        self.content = content
        super.init(frame: .zero)
        setupContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - FeedCellContentUpdatable

    func updateIsActive(_ active: Bool) {
        videoView?.setActive(active)
    }

    // MARK: - Setup

    private func setupContent() {
        backgroundColor = .black
        switch content {
        case .video(let asset, let isActive, let sharedPlayer):
            let v = VideoContentView(asset: asset, isActive: isActive, sharedPlayer: sharedPlayer)
            videoView = v
            addAndPin(v)
        case .photoCarousel(let assets):
            let v = PhotoCarouselContentView(assets: assets)
            photoView = v
            addAndPin(v)
        }
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

    // MARK: - Lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            videoView?.tearDown()
            photoView?.tearDown()
        }
    }
}

// MARK: - Video Content

private final class VideoContentView: UIView {

    private let asset: PHAsset
    private var isActive: Bool
    private let sharedPlayer: SingleAssetPlayer?
    private let ownPlayer = SingleAssetPlayer()
    private var player: SingleAssetPlayer { sharedPlayer ?? ownPlayer }
    private var usesSharedPlayer: Bool { sharedPlayer != nil }
    private let playerLayerView = PlayerLayerView()

    init(asset: PHAsset, isActive: Bool, sharedPlayer: SingleAssetPlayer?) {
        self.asset = asset
        self.isActive = isActive
        self.sharedPlayer = sharedPlayer
        super.init(frame: .zero)
        setupView()
        configurePlayback()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        if active {
            player.setAsset(asset)
            player.setActive(true)
            CurrentPlayback.shared.currentAssetID = asset.localIdentifier
        } else {
            player.setActive(false)
        }
    }

    func tearDown() {
        if usesSharedPlayer {
            player.setActive(false)
        } else {
            player.cancel()
        }
    }

    private func setupView() {
        backgroundColor = .black
        playerLayerView.backgroundColor = .black
        playerLayerView.playerLayer.videoGravity = .resizeAspectFill
        playerLayerView.playerLayer.player = player.player
        addSubview(playerLayerView)
        playerLayerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerLayerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerLayerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerLayerView.topAnchor.constraint(equalTo: topAnchor),
            playerLayerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    private func configurePlayback() {
        if usesSharedPlayer {
            if isActive {
                player.setAsset(asset)
                player.setActive(true)
                CurrentPlayback.shared.currentAssetID = asset.localIdentifier
            } else {
                player.setActive(false)
            }
        } else {
            player.setAsset(asset)
            player.setActive(isActive)
            if isActive {
                CurrentPlayback.shared.currentAssetID = asset.localIdentifier
            }
        }
    }

    @objc private func handleTap() {
        guard isActive else { return }
        player.togglePlay()
    }
}

// MARK: - Photo Carousel Content

private final class PhotoCarouselContentView: UIView {

    private let assets: [PHAsset]
    private let collectionView: UICollectionView
    private let pageControl = UIPageControl()
    private let layout: UICollectionViewFlowLayout
    private var loadTaskCancellables: [IndexPath: Task<Void, Never>] = [:]

    init(assets: [PHAsset]) {
        self.assets = assets
        self.layout = UICollectionViewFlowLayout()
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        setupCollectionView()
        setupPageControl()
        setupConstraints()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func tearDown() {
        loadTaskCancellables.values.forEach { $0.cancel() }
        loadTaskCancellables.removeAll()
    }

    private func setupCollectionView() {
        backgroundColor = .black
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(PhotoCarouselPageCell.self, forCellWithReuseIdentifier: PhotoCarouselPageCell.reuseId)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionView)
    }

    private func setupPageControl() {
        pageControl.numberOfPages = max(1, assets.count)
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = .white
        pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.35)
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.isHidden = assets.count <= 1
        addSubview(pageControl)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pageControl.centerXAnchor.constraint(equalTo: centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -28)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        layout.itemSize = bounds.size
    }

    private func loadImage(for cell: PhotoCarouselPageCell, at indexPath: IndexPath) {
        guard assets.indices.contains(indexPath.item) else { return }
        let asset = assets[indexPath.item]
        let assetID = asset.localIdentifier
        loadTaskCancellables[indexPath]?.cancel()
        cell.cancelPendingLoad()
        cell.setExpectedAssetID(assetID)
        let scale = UIScreen.main.scale
        let w = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let h = bounds.height > 0 ? bounds.height : UIScreen.main.bounds.height
        let targetSize = CGSize(
            width: min(max(1, w) - MediaFeedConstants.horizontalPadding * 2, CGFloat(asset.pixelWidth)) * scale,
            height: min(max(1, h) * MediaFeedConstants.maxHeightFraction, CGFloat(asset.pixelHeight)) * scale
        )
        guard targetSize.width > 0, targetSize.height > 0 else { return }
        let task = Task { @MainActor in
            let image = await ImagePrefetcher.shared.requestImage(for: asset, targetSize: targetSize)
            guard !Task.isCancelled else { return }
            cell.applyImageIfMatching(image, assetID: assetID)
        }
        loadTaskCancellables[indexPath] = task
        cell.setLoadTask(task)
    }

    private func cancelLoad(for indexPath: IndexPath) {
        loadTaskCancellables[indexPath]?.cancel()
        loadTaskCancellables.removeValue(forKey: indexPath)
    }
}

extension PhotoCarouselContentView: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        assets.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoCarouselPageCell.reuseId, for: indexPath) as! PhotoCarouselPageCell
        loadImage(for: cell, at: indexPath)
        return cell
    }
}

extension PhotoCarouselContentView: UICollectionViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard bounds.width > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / bounds.width))
        pageControl.currentPage = min(max(0, page), assets.count - 1)
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
        v.contentMode = .scaleAspectFit
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var expectedAssetID: String?
    private var loadTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: MediaFeedConstants.horizontalPadding),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -MediaFeedConstants.horizontalPadding),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.heightAnchor.constraint(lessThanOrEqualTo: contentView.heightAnchor, multiplier: MediaFeedConstants.maxHeightFraction)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setExpectedAssetID(_ assetID: String) {
        expectedAssetID = assetID
    }

    func setLoadTask(_ task: Task<Void, Never>) {
        loadTask = task
    }

    func cancelPendingLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    func applyImageIfMatching(_ image: UIImage?, assetID: String) {
        guard expectedAssetID == assetID else { return }
        imageView.image = image
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelPendingLoad()
        imageView.image = nil
        expectedAssetID = nil
    }
}
