//
//  AlbumHorizontalCarouselViewController.swift
//  Names 3
//
//  Horizontal full-screen carousel for a ProfileItem (album or single asset).
//  Swipe left/right to browse. Replaces the vertical feed for album detail.
//

import UIKit
import Photos
import AVFoundation
import SwiftUI

// MARK: - AlbumHorizontalCarouselViewController

@MainActor
final class AlbumHorizontalCarouselViewController: UIViewController {

    // MARK: - Properties

    private let item: ProfileItem
    private let initialIndex: Int

    private var assets: [PHAsset] = []
    private var feedItems: [FeedItem] = []
    private var collectionView: UICollectionView!
    private var currentIndex: Int = 0
    private var carouselCurrentPage: [Int: Int] = [:]

    // MARK: - Init

    init(item: ProfileItem, initialIndex: Int = 0) {
        self.item = item
        self.initialIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    /// Direct assets (e.g. for Save sheet). Uses assets directly; item is a placeholder.
    convenience init(assets: [PHAsset], initialIndex: Int = 0) {
        let item: ProfileItem = .asset(assets[0])
        self.init(item: item, initialIndex: initialIndex)
        self._directAssets = assets
    }

    private var _directAssets: [PHAsset]?

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        loadAssets()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if isMovingFromParent || isBeingDismissed {
            if FeatureFlags.enableAppleMusicIntegration {
                AppleMusicController.shared.pauseIfManaged()
                AppleMusicController.shared.stopManaging()
            }
        }
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Data Loading

    private func loadAssets() {
        Task {
            let fetched: [PHAsset]
            if let direct = _directAssets {
                fetched = direct
            } else {
                switch item {
                case .album(let collection):
                    let options = PHFetchOptions()
                    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                    let result = PHAsset.fetchAssets(in: collection, options: options)
                    var list: [PHAsset] = []
                    result.enumerateObjects { asset, _, _ in list.append(asset) }
                    fetched = list
                case .asset(let a):
                    fetched = [a]
                }
            }
            self.assets = fetched
            self.feedItems = Self.buildFeedItems(from: fetched)
            if !feedItems.isEmpty {
                preloadSongForAlbumEntry()
                buildHorizontalCarousel()
            } else {
                showEmptyState()
            }
        }
    }

    /// Bootstrap Music and start the album's song so it plays immediately when the first cell appears.
    private func preloadSongForAlbumEntry() {
        guard FeatureFlags.enableAppleMusicIntegration else { return }
        let firstAssetID = FeedItem.flattenToAssets(feedItems).first?.localIdentifier
        let idx = max(0, min(initialIndex, feedItems.count - 1))
        let assetID = feedItems.indices.contains(idx)
            ? FeedItem.flattenToAssets([feedItems[idx]]).first?.localIdentifier ?? firstAssetID
            : firstAssetID
        Task { @MainActor in
            await MusicBootstrapper.shared.ensureBootstrapped()
            let ref = await VideoAudioOverrides.shared.songReference(for: assetID)
            if let ref {
                AppleMusicController.shared.play(reference: ref)
            }
        }
    }

    private static func buildFeedItems(from assets: [PHAsset]) -> [FeedItem] {
        assets.map { asset in
            switch asset.mediaType {
            case .video:
                return FeedItem.video(asset)
            default:
                return FeedItem.carousel([asset])
            }
        }
    }

    // MARK: - Horizontal Carousel

    private func buildHorizontalCarousel() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.estimatedItemSize = .zero

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .black
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(HorizontalCarouselCell.self, forCellWithReuseIdentifier: HorizontalCarouselCell.reuseID)
        view.addSubview(collectionView)

        let clamped = max(0, min(feedItems.count - 1, initialIndex))
        currentIndex = clamped
        if clamped > 0 {
            collectionView.layoutIfNeeded()
            collectionView.scrollToItem(at: IndexPath(item: clamped, section: 0), at: .centeredHorizontally, animated: false)
        }

        addCloseButton()
        addMusicButton()
    }

    private func buildContentView(for item: FeedItem, index: Int, isActive: Bool) -> UIView {
        switch item.kind {
        case .video(let asset):
            return MediaFeedCellView(content: .video(asset: asset, isActive: isActive, sharedPlayer: nil))
        case .photoCarousel(let assets):
            return MediaFeedCellView(content: .photoCarousel(assets))
        }
    }

    // MARK: - UI Helpers

    private func addCloseButton() {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 18
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36),
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
        ])
    }

    private func addMusicButton() {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        button.setImage(UIImage(systemName: "music.note", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 22
        button.addTarget(self, action: #selector(musicTapped), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
        button.accessibilityLabel = "Assign music"
    }

    @objc private func musicTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        let assetIDs = FeedItem.flattenToAssets(feedItems).map { $0.localIdentifier }
        let currentAssetID = assetIDs.indices.contains(currentIndex) ? assetIDs[currentIndex] : assetIDs.first
        let screen = AppleMusicSearchScreen(assetID: currentAssetID) { [weak self] in
            self?.dismiss(animated: true)
        }
        let hosting = UIHostingController(rootView: screen)
        hosting.modalPresentationStyle = .pageSheet
        if let sheet = hosting.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(hosting, animated: true)
    }

    private func showEmptyState() {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "No photos"
        label.font = .systemFont(ofSize: 17)
        label.textColor = .white
        label.textAlignment = .center
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        addCloseButton()
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - UICollectionViewDataSource, UICollectionViewDelegateFlowLayout

extension AlbumHorizontalCarouselViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        feedItems.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: HorizontalCarouselCell.reuseID, for: indexPath) as! HorizontalCarouselCell
        let feedItem = feedItems[indexPath.item]
        let isActive = (indexPath.item == currentIndex)
        let content = buildContentView(for: feedItem, index: indexPath.item, isActive: isActive)
        cell.configure(content: content, isActive: isActive)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }
}

// MARK: - UIScrollViewDelegate (paging)

extension AlbumHorizontalCarouselViewController: UIScrollViewDelegate {

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateActivePage(from: scrollView)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateActivePage(from: scrollView)
    }

    private func updateActivePage(from scrollView: UIScrollView) {
        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / pageWidth))
        guard page != currentIndex, feedItems.indices.contains(page) else { return }
        let oldIndex = currentIndex
        currentIndex = page
        if let oldCell = collectionView.cellForItem(at: IndexPath(item: oldIndex, section: 0)) as? HorizontalCarouselCell {
            oldCell.setActive(false)
        }
        if let newCell = collectionView.cellForItem(at: IndexPath(item: page, section: 0)) as? HorizontalCarouselCell {
            newCell.setActive(true)
        }
    }
}

// MARK: - HorizontalCarouselCell

private final class HorizontalCarouselCell: UICollectionViewCell {

    static let reuseID = "HorizontalCarouselCell"

    private var contentHost: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentHost?.removeFromSuperview()
        contentHost = nil
    }

    func configure(content: UIView, isActive: Bool) {
        contentHost?.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: contentView.topAnchor),
            content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        contentHost = content
        if let updatable = content as? FeedCellContentUpdatable {
            updatable.updateIsActive(isActive)
        }
    }

    func setActive(_ active: Bool) {
        (contentHost as? FeedCellContentUpdatable)?.updateIsActive(active)
    }
}
