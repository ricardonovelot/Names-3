//
//  AlbumPickerViewController.swift
//  Names 3
//
//  Sheet that shows albums and option to add individual photos from gallery.
//

import UIKit
import Photos
import PhotosUI

// MARK: - AlbumPickerViewController

@MainActor
final class AlbumPickerViewController: UIViewController {

    // MARK: - Properties

    private let store = AlbumStore.shared
    private var allAlbums: [PHAssetCollection] = []
    private var coverCache: [String: UIImage] = [:]

    // MARK: - UI

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!

    private lazy var doneButton: UIBarButtonItem = UIBarButtonItem(
        barButtonSystemItem: .done,
        target: self,
        action: #selector(doneTapped)
    )

    private lazy var addPhotoButton: UIBarButtonItem = UIBarButtonItem(
        image: UIImage(systemName: "photo.on.rectangle.angled"),
        style: .plain,
        target: self,
        action: #selector(addPhotoTapped)
    )

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "Add to Profile"
        navigationItem.leftBarButtonItem = addPhotoButton
        navigationItem.rightBarButtonItem = doneButton
        setupCollectionView()
        setupDataSource()
        loadAlbums()
    }

    // MARK: - Setup

    private func setupCollectionView() {
        collectionView = UICollectionView(
            frame: view.bounds,
            collectionViewLayout: makeLayout()
        )
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.delegate = self
        collectionView.register(AlbumPickerCell.self, forCellWithReuseIdentifier: AlbumPickerCell.reuseID)
        view.addSubview(collectionView)
    }

    private func makeLayout() -> UICollectionViewLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.backgroundColor = .systemGroupedBackground
        config.trailingSwipeActionsConfigurationProvider = nil
        return UICollectionViewCompositionalLayout.list(using: config)
    }

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, identifier in
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: AlbumPickerCell.reuseID,
                for: indexPath
            ) as! AlbumPickerCell

            guard let self,
                  let collection = self.allAlbums.first(where: { $0.localIdentifier == identifier })
            else { return cell }

            let alreadyAdded = self.store.contains(collection)
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            cell.configure(
                title: collection.localizedTitle ?? "Untitled",
                count: count,
                coverImage: self.coverCache[identifier],
                isAdded: alreadyAdded
            )
            if self.coverCache[identifier] == nil {
                self.loadCover(for: collection, identifier: identifier) { [weak cell] image in
                    cell?.setCoverImage(image)
                }
            }
            return cell
        }
    }

    // MARK: - Data Loading

    private func loadAlbums() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "localizedTitle", ascending: true)]
        let result = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: options
        )
        var albums: [PHAssetCollection] = []
        result.enumerateObjects { collection, _, _ in
            // Only show albums with at least one asset
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            if count > 0 { albums.append(collection) }
        }
        allAlbums = albums

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(albums.map(\.localIdentifier))
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func loadCover(
        for collection: PHAssetCollection,
        identifier: String,
        completion: @escaping (UIImage?) -> Void
    ) {
        Task {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 1
            guard let asset = PHAsset.fetchAssets(in: collection, options: options).firstObject else {
                completion(nil)
                return
            }
            let image = await PhotoLibraryService.shared.requestImage(
                for: asset,
                targetSize: CGSize(width: 120, height: 120),
                contentMode: .aspectFill
            )
            self.coverCache[identifier] = image
            completion(image)
        }
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    @objc private func addPhotoTapped() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0  // Unlimited
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension AlbumPickerViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        let identifiers = results.compactMap { $0.assetIdentifier }
        guard !identifiers.isEmpty else { return }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var added = 0
        fetchResult.enumerateObjects { asset, _, _ in
            if !self.store.contains(asset) {
                self.store.addAsset(asset)
                added += 1
            }
        }
        if added > 0 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.dismiss(animated: true)
            }
        }
    }
}

// MARK: - UICollectionViewDelegate

extension AlbumPickerViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard allAlbums.indices.contains(indexPath.item) else { return }
        let collection = allAlbums[indexPath.item]
        guard !store.contains(collection) else { return }
        store.addAlbum(collection)
        // Reload to show checkmark
        var snapshot = dataSource.snapshot()
        snapshot.reloadItems([collection.localIdentifier])
        dataSource.apply(snapshot, animatingDifferences: true)
        // Small delay so user sees the checkmark, then dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.dismiss(animated: true)
        }
    }
}

// MARK: - AlbumPickerCell

private final class AlbumPickerCell: UICollectionViewCell {

    static let reuseID = "AlbumPickerCell"

    private let thumbnailView = UIImageView()
    private let nameLabel = UILabel()
    private let countLabel = UILabel()
    private let checkmarkView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.image = nil
    }

    func configure(title: String, count: Int, coverImage: UIImage?, isAdded: Bool) {
        nameLabel.text = title
        countLabel.text = "\(count) items"
        thumbnailView.image = coverImage
        checkmarkView.isHidden = !isAdded
        contentView.alpha = isAdded ? 0.55 : 1.0
    }

    func setCoverImage(_ image: UIImage?) {
        UIView.transition(with: thumbnailView, duration: 0.2, options: .transitionCrossDissolve) {
            self.thumbnailView.image = image
        }
    }

    private func setup() {
        backgroundColor = .secondarySystemGroupedBackground

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 8
        thumbnailView.backgroundColor = .tertiarySystemFill

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 16, weight: .regular)
        nameLabel.textColor = .label

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 13, weight: .regular)
        countLabel.textColor = .secondaryLabel

        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkView.image = UIImage(systemName: "checkmark.circle.fill")
        checkmarkView.tintColor = .systemGreen
        checkmarkView.isHidden = true

        let textStack = UIStackView(arrangedSubviews: [nameLabel, countLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 3

        contentView.addSubview(thumbnailView)
        contentView.addSubview(textStack)
        contentView.addSubview(checkmarkView)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 52),
            thumbnailView.heightAnchor.constraint(equalToConstant: 52),
            thumbnailView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 10),
            thumbnailView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            textStack.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 14),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: checkmarkView.leadingAnchor, constant: -12),

            checkmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkmarkView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmarkView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
}
