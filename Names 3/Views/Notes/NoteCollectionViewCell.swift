//
//  NoteCollectionViewCell.swift
//  Names 3
//
//  Grid cell for the notes feed. Contact photo bleeds through at low opacity
//  as background; contact name and note content are layered on top.
//

import UIKit

@MainActor
final class NoteCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "NoteCollectionViewCell"

    // MARK: - Subviews

    private let photoImageView = UIImageView()
    private let readabilityGradient = CAGradientLayer()
    private let nameLabel = UILabel()
    private let contentLabel = UILabel()
    private let nameSeparator = UIView()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        readabilityGradient.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        photoImageView.image = nil
        nameLabel.text = nil
        contentLabel.text = nil
    }

    // MARK: - Configuration

    func configure(note: Note) {
        if let photoData = note.contact?.photo, !photoData.isEmpty,
           let image = UIImage(data: photoData) {
            photoImageView.image = image
            photoImageView.isHidden = false
        } else {
            photoImageView.image = nil
            photoImageView.isHidden = true
        }

        nameLabel.text = note.contact?.name ?? ""
        contentLabel.text = note.content
    }

    // MARK: - Setup

    private func setupViews() {
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 10
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        // Photo background at low opacity — the contact's face peers through the words
        photoImageView.contentMode = .scaleAspectFill
        photoImageView.clipsToBounds = true
        photoImageView.alpha = 0.28
        photoImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(photoImageView)

        // Subtle gradient from transparent to the cell background at the bottom
        // so text stays legible regardless of the photo content
        readabilityGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.45).cgColor
        ]
        readabilityGradient.locations = [0.3, 1.0]
        readabilityGradient.startPoint = CGPoint(x: 0.5, y: 0)
        readabilityGradient.endPoint = CGPoint(x: 0.5, y: 1)
        contentView.layer.addSublayer(readabilityGradient)

        // Contact name — tiny and secondary, anchored at the top
        nameLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        nameLabel.textColor = .secondaryLabel
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 1
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        // One-pixel separator between name and content
        nameSeparator.backgroundColor = .separator
        nameSeparator.alpha = 0.5
        nameSeparator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameSeparator)

        // Note content — the star of the cell
        contentLabel.font = .systemFont(ofSize: 12, weight: .regular)
        contentLabel.textColor = .label
        contentLabel.adjustsFontForContentSizeCategory = true
        contentLabel.numberOfLines = 0
        contentLabel.lineBreakMode = .byTruncatingTail
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentLabel)

        NSLayoutConstraint.activate([
            photoImageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            photoImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            photoImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            photoImageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            nameSeparator.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            nameSeparator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            nameSeparator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            nameSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            contentLabel.topAnchor.constraint(equalTo: nameSeparator.bottomAnchor, constant: 5),
            contentLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            contentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            contentLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8)
        ])
    }
}
