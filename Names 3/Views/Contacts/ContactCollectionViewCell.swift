//
//  ContactCollectionViewCell.swift
//  Names 3
//
//  UIKit collection view cell for a persisted contact. Photo, name, context menu.
//

import UIKit
import SwiftData

final class ContactCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "ContactCollectionViewCell"

    var onChangeDate: (() -> Void)?
    var onDelete: (() -> Void)?

    private let imageView = UIImageView()
    private let gradientLayer = CAGradientLayer()
    private let glassContainerView = UIView()
    private let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let radialGradientLayer = CAGradientLayer()
    private let strokeLayer = CAShapeLayer()
    private let nameLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = contentView.bounds
        radialGradientLayer.frame = glassContainerView.bounds
        radialGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        radialGradientLayer.endPoint = CGPoint(x: 1.2, y: 0.5)
        strokeLayer.path = UIBezierPath(roundedRect: contentView.bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 9.5).cgPath
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        nameLabel.text = nil
        onChangeDate = nil
        onDelete = nil
    }

    func configure(with contact: Contact) {
        nameLabel.text = contact.name ?? ""

        if !contact.photo.isEmpty, let image = UIImage(data: contact.photo) {
            imageView.image = image
            imageView.isHidden = false
            gradientLayer.isHidden = false
            glassContainerView.isHidden = true
            nameLabel.textColor = .white.withAlphaComponent(0.9)
        } else {
            imageView.image = nil
            imageView.isHidden = true
            gradientLayer.isHidden = true
            glassContainerView.isHidden = false
            nameLabel.textColor = .label.withAlphaComponent(0.8)
        }
    }

    private func setupViews() {
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 10
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        glassContainerView.backgroundColor = .clear
        glassContainerView.layer.cornerRadius = 10
        glassContainerView.layer.cornerCurve = .continuous
        glassContainerView.clipsToBounds = true
        glassContainerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(glassContainerView)

        if #available(iOS 12.1, *) {
            radialGradientLayer.type = .radial
        }
        radialGradientLayer.colors = [
            UIColor.secondarySystemBackground.cgColor,
            UIColor.tertiarySystemBackground.cgColor
        ]
        radialGradientLayer.cornerRadius = 10
        radialGradientLayer.cornerCurve = .continuous
        glassContainerView.layer.insertSublayer(radialGradientLayer, at: 0)

        blurEffectView.layer.cornerRadius = 10
        blurEffectView.layer.cornerCurve = .continuous
        blurEffectView.clipsToBounds = true
        blurEffectView.translatesAutoresizingMaskIntoConstraints = false
        glassContainerView.addSubview(blurEffectView)

        strokeLayer.fillColor = nil
        strokeLayer.strokeColor = UIColor.white.withAlphaComponent(0.18).cgColor
        strokeLayer.lineWidth = 0.5
        strokeLayer.lineCap = .round
        strokeLayer.lineJoin = .round
        glassContainerView.layer.addSublayer(strokeLayer)

        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.6).cgColor
        ]
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        contentView.layer.addSublayer(gradientLayer)

        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            glassContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            glassContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            glassContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            glassContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            blurEffectView.topAnchor.constraint(equalTo: glassContainerView.topAnchor),
            blurEffectView.leadingAnchor.constraint(equalTo: glassContainerView.leadingAnchor),
            blurEffectView.trailingAnchor.constraint(equalTo: glassContainerView.trailingAnchor),
            blurEffectView.bottomAnchor.constraint(equalTo: glassContainerView.bottomAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            nameLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])

        addInteraction(UIContextMenuInteraction(delegate: self))
    }
}

extension ContactCollectionViewCell: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Change Date", image: UIImage(systemName: "calendar")) { _ in
                    self?.onChangeDate?()
                },
                UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self?.onDelete?()
                }
            ])
        }
    }
}
