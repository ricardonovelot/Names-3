//
//  ContactsFeedEmptyStateView.swift
//  Names 3
//
//  UIKit empty state view for the contacts feed.
//

import UIKit

final class ContactsFeedEmptyStateView: UIView {

    private let stackView = UIStackView()
    private let iconImageView = UIImageView()
    private let progressView = UIActivityIndicatorView(style: .large)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let hintLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(showSyncing: Bool, showNoStorage: Bool) {
        progressView.isHidden = !showSyncing
        iconImageView.isHidden = showSyncing

        if showSyncing {
            progressView.startAnimating()
            titleLabel.text = String(localized: "feed.empty.syncing")
            subtitleLabel.text = nil
            hintLabel.text = nil
        } else if showNoStorage {
            progressView.stopAnimating()
            iconImageView.image = UIImage(systemName: "externaldrive.fill.badge.exclamationmark")
            iconImageView.tintColor = .secondaryLabel
            titleLabel.text = String(localized: "feed.empty.no_storage.title")
            subtitleLabel.text = String(localized: "feed.empty.no_storage.message")
            hintLabel.text = nil
        } else {
            progressView.stopAnimating()
            iconImageView.image = UIImage(systemName: "person.2.fill")
            iconImageView.tintColor = .secondaryLabel
            titleLabel.text = String(localized: "feed.empty.title")
            subtitleLabel.text = String(localized: "feed.empty.subtitle")
            hintLabel.text = String(localized: "feed.empty.icloud.hint")
        }

        subtitleLabel.isHidden = subtitleLabel.text == nil || subtitleLabel.text?.isEmpty == true
        hintLabel.isHidden = hintLabel.text == nil || hintLabel.text?.isEmpty == true
    }

    private func setupViews() {
        backgroundColor = .systemGroupedBackground

        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false

        progressView.hidesWhenStopped = true
        progressView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.adjustsFontForContentSizeCategory = true

        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.adjustsFontForContentSizeCategory = true

        stackView.addArrangedSubview(progressView)
        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(hintLabel)

        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 40),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -80)
        ])
    }
}
