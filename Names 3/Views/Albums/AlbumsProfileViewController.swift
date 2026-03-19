//
//  AlbumsProfileViewController.swift
//  Names 3
//
//  Instagram/TikTok profile-style albums grid. Users start with no albums and
//  explicitly add albums they want to appear here.
//

import UIKit
import Photos
import Combine

// MARK: - AlbumsProfileViewController

@MainActor
final class AlbumsProfileViewController: UIViewController {

    // MARK: - Layout Constants

    private enum Layout {
        static let columns: CGFloat = 3
        static let spacing: CGFloat = 2
        static let headerHeight: CGFloat = 180
        static let sectionInset = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 2, trailing: 0)
    }

    // MARK: - Properties

    private let store = AlbumStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var items: [ProfileItem] = []
    private var coverCache: [String: UIImage] = [:]

    var bottomBarHeight: CGFloat = 0 {
        didSet {
            guard let cv = collectionView else { return }
            var inset = cv.contentInset
            inset.bottom = bottomBarHeight
            cv.contentInset = inset
            var indicators = cv.verticalScrollIndicatorInsets
            indicators.bottom = bottomBarHeight
            cv.verticalScrollIndicatorInsets = indicators
        }
    }

    // MARK: - UI Components

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!

    private lazy var addButton: UIBarButtonItem = {
        UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addAlbumTapped)
        )
    }()

    private lazy var emptyStateView: EmptyStateView = {
        let v = EmptyStateView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.onAddTapped = { [weak self] in self?.addAlbumTapped() }
        return v
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupCollectionView()
        setupDataSource()
        setupEmptyState()
        bindStore()
        reload()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = addButton
        // Large title style like Instagram profile
        navigationController?.navigationBar.prefersLargeTitles = false
    }

    private func setupCollectionView() {
        collectionView = UICollectionView(
            frame: view.bounds,
            collectionViewLayout: makeLayout()
        )
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.showsVerticalScrollIndicator = true
        var inset = collectionView.contentInset
        inset.bottom = bottomBarHeight
        collectionView.contentInset = inset
        var indicators = collectionView.verticalScrollIndicatorInsets
        indicators.bottom = bottomBarHeight
        collectionView.verticalScrollIndicatorInsets = indicators
        collectionView.delegate = self
        collectionView.register(AlbumCoverCell.self, forCellWithReuseIdentifier: AlbumCoverCell.reuseID)
        collectionView.register(
            ProfileHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: ProfileHeaderView.reuseID
        )
        view.addSubview(collectionView)
    }

    private func makeLayout() -> UICollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / Layout.columns),
            heightDimension: .fractionalWidth(1.0 / Layout.columns)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(
            top: Layout.spacing / 2,
            leading: Layout.spacing / 2,
            bottom: Layout.spacing / 2,
            trailing: Layout.spacing / 2
        )

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalWidth(1.0 / Layout.columns)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = Layout.sectionInset

        let headerSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(Layout.headerHeight)
        )
        let header = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
        section.boundarySupplementaryItems = [header]

        return UICollectionViewCompositionalLayout(section: section)
    }

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Int, String>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, identifier in
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: AlbumCoverCell.reuseID,
                for: indexPath
            ) as! AlbumCoverCell

            guard let self,
                  let item = self.items.first(where: { $0.identifier == identifier })
            else { return cell }

            let cached = self.coverCache[identifier]
            cell.configure(
                item: item,
                coverImage: cached,
                onNeedsCover: { [weak self, weak cell] in
                    self?.loadCover(for: item, identifier: identifier) { image in
                        if let currentCell = collectionView.cellForItem(at: indexPath) as? AlbumCoverCell {
                            currentCell.setCoverImage(image)
                        } else {
                            cell?.setCoverImage(image)
                        }
                    }
                }
            )
            return cell
        }

        dataSource.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionHeader else { return nil }
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: ProfileHeaderView.reuseID,
                for: indexPath
            ) as! ProfileHeaderView
            header.configure(itemCount: self?.items.count ?? 0)
            return header
        }
    }

    private func setupEmptyState() {
        view.addSubview(emptyStateView)
        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }

    // MARK: - Store Binding

    private func bindStore() {
        store.$savedIdentifiers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    // MARK: - Data Loading

    private func reload() {
        items = store.resolvedItems()
        let isEmpty = items.isEmpty
        emptyStateView.isHidden = !isEmpty
        collectionView.isHidden = isEmpty

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(items.map(\.identifier))
        dataSource.apply(snapshot, animatingDifferences: true)

        if var headerSnapshot = dataSource?.snapshot() {
            headerSnapshot.reloadSections([0])
        }
    }

    private func loadCover(
        for item: ProfileItem,
        identifier: String,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard coverCache[identifier] == nil else {
            completion(coverCache[identifier])
            return
        }

        Task {
            let asset: PHAsset?
            switch item {
            case .album(let collection):
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.fetchLimit = 1
                asset = PHAsset.fetchAssets(in: collection, options: options).firstObject
            case .asset(let a):
                asset = a
            }
            guard let a = asset else {
                completion(nil)
                return
            }
            let size = CGSize(width: 300, height: 300)
            let image = await PhotoLibraryService.shared.requestImage(
                for: a,
                targetSize: size,
                contentMode: .aspectFill
            )
            self.coverCache[identifier] = image
            completion(image)
        }
    }

    // MARK: - Actions

    private func confirmAndRemoveItem(withIdentifier id: String) {
        let alert = UIAlertController(
            title: "Remove from Profile",
            message: "Remove this from your profile?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.store.removeItem(withIdentifier: id)
        })
        present(alert, animated: true)
    }

    @objc private func addAlbumTapped() {
        let picker = AlbumPickerViewController()
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }
}

// MARK: - UICollectionViewDelegate

extension AlbumsProfileViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard items.indices.contains(indexPath.item) else { return }
        let item = items[indexPath.item]
        let carousel = AlbumHorizontalCarouselViewController(item: item)
        navigationController?.pushViewController(carousel, animated: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              items.indices.contains(indexPath.item)
        else { return nil }

        let id = items[indexPath.item].identifier
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            let removeAction = UIAction(
                title: "Remove from Profile",
                image: UIImage(systemName: "minus.circle"),
                attributes: .destructive
            ) { _ in
                self?.confirmAndRemoveItem(withIdentifier: id)
            }
            return UIMenu(children: [removeAction])
        })
    }
}

// MARK: - ProfileHeaderView

private final class ProfileHeaderView: UICollectionReusableView {

    static let reuseID = "ProfileHeaderView"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let divider = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(itemCount: Int) {
        let countText = itemCount == 1
            ? "1 item"
            : "\(itemCount) items"
        subtitleLabel.text = countText
    }

    private func setup() {
        backgroundColor = .systemBackground

        // App icon / graphic
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: "photo.on.rectangle.angled")
        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit

        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Albums"
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = .label

        // Subtitle
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel

        // Divider
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .separator

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(divider)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),

            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }
}

// MARK: - AlbumCoverCell

final class AlbumCoverCell: UICollectionViewCell {

    static let reuseID = "AlbumCoverCell"

    private let imageView = UIImageView()
    private let gradientLayer = CAGradientLayer()
    private let nameLabel = UILabel()
    private let countLabel = UILabel()

    private var onNeedsCover: (() -> Void)?
    private var loadedIdentifier: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        loadedIdentifier = nil
        onNeedsCover = nil
    }

    func configure(
        item: ProfileItem,
        coverImage: UIImage?,
        onNeedsCover: @escaping () -> Void
    ) {
        nameLabel.text = item.displayTitle ?? "Photo"
        countLabel.text = item.assetCount > 1 ? "\(item.assetCount)" : ""

        loadedIdentifier = item.identifier
        self.onNeedsCover = onNeedsCover

        if let image = coverImage {
            imageView.image = image
        } else {
            imageView.image = nil
            onNeedsCover()
        }
    }

    func setCoverImage(_ image: UIImage?) {
        UIView.transition(with: imageView, duration: 0.2, options: .transitionCrossDissolve) {
            self.imageView.image = image
        }
    }

    private func setup() {
        clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = UIColor.secondarySystemBackground
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // Gradient overlay (bottom to transparent)
        gradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.7).cgColor]
        gradientLayer.locations = [0.5, 1.0]
        contentView.layer.addSublayer(gradientLayer)

        // Album name
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.numberOfLines = 2
        contentView.addSubview(nameLabel)

        // Asset count
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        contentView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            countLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            countLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -6),

            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -6),
            nameLabel.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -2)
        ])
    }
}

// MARK: - EmptyStateView

private final class EmptyStateView: UIView {

    var onAddTapped: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        let icon = UIImageView(image: UIImage(systemName: "photo.stack"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .tertiaryLabel
        icon.contentMode = .scaleAspectFit

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "No Albums Yet"
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .label
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "Add albums from your photo library\nto see them here."
        subtitle.font = .systemFont(ofSize: 15, weight: .regular)
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        let addButton = UIButton(type: .system)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.plain()
        config.title = "Add Your First Album"
        config.baseForegroundColor = .systemBackground
        config.background.backgroundColor = .label
        config.background.cornerRadius = 22
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24)
        addButton.configuration = config
        addButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle, addButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.setCustomSpacing(20, after: subtitle)

        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @objc private func buttonTapped() {
        onAddTapped?()
    }
}
