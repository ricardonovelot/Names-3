//
//  ContactsFeedGroupHeaderView.swift
//  Names 3
//
//  Section header for a contacts group. Title, subtitle, visible menu button.
//

import UIKit

final class ContactsFeedGroupHeaderView: UICollectionReusableView, UIContextMenuInteractionDelegate {

    static let reuseIdentifier = "ContactsFeedGroupHeaderView"

    var onTap: (() -> Void)?
    var onImport: (() -> Void)?
    var onEditDate: (() -> Void)?
    var onEditTag: (() -> Void)?
    var onDeleteAll: (() -> Void)?

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stackView = UIStackView()
    private let menuButton = UIButton(type: .system)
    private var isLongAgo = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, subtitle: String, isLongAgo: Bool) {
        self.isLongAgo = isLongAgo
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle.isEmpty
        menuButton.isHidden = isLongAgo
        menuButton.isUserInteractionEnabled = !isLongAgo
    }

    /// Call after setting all callbacks (e.g. from supplementaryViewProvider) to wire the menu button.
    func prepareMenuButton() {
        updateMenuButtonMenu()
    }

    private func setupViews() {
        // Title: large, bold, clear hierarchy
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2

        // Subtitle: smaller, secondary
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 1

        stackView.axis = .vertical
        stackView.spacing = 2
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.isUserInteractionEnabled = false
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)

        // Full-width button behind title: tap shows menu. Title on top so it's visible.
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.backgroundColor = .clear
        addSubview(menuButton)
        addSubview(stackView)

        addInteraction(UIContextMenuInteraction(delegate: self))
        isUserInteractionEnabled = true

        NSLayoutConstraint.activate([
            menuButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            menuButton.topAnchor.constraint(equalTo: topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: 0),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    private func updateMenuButtonMenu() {
        guard !isLongAgo else {
            menuButton.menu = nil
            return
        }
        menuButton.menu = UIMenu(children: [
            UIAction(title: "Open in Gallery", image: UIImage(systemName: "photo.on.rectangle.angled")) { [weak self] _ in
                self?.onTap?()
            },
            UIAction(title: "Import Photos", image: UIImage(systemName: "photo.on.rectangle")) { [weak self] _ in
                self?.onImport?()
            },
            UIAction(title: "Change Date", image: UIImage(systemName: "calendar")) { [weak self] _ in
                self?.onEditDate?()
            },
            UIAction(title: "Change Place", image: UIImage(systemName: "tag")) { [weak self] _ in
                self?.onEditTag?()
            },
            UIAction(title: "Delete All", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.onDeleteAll?()
            }
        ])
        menuButton.showsMenuAsPrimaryAction = true
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isLongAgo else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Open in Gallery", image: UIImage(systemName: "photo.on.rectangle.angled")) { _ in
                    self?.onTap?()
                },
                UIAction(title: "Import Photos", image: UIImage(systemName: "photo.on.rectangle")) { _ in
                    self?.onImport?()
                },
                UIAction(title: "Change Date", image: UIImage(systemName: "calendar")) { _ in
                    self?.onEditDate?()
                },
                UIAction(title: "Change Place", image: UIImage(systemName: "tag")) { _ in
                    self?.onEditTag?()
                },
                UIAction(title: "Delete All", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self?.onDeleteAll?()
                }
            ])
        }
    }
}
