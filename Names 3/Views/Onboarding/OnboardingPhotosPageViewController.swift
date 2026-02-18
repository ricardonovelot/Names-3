//
//  OnboardingPhotosPageViewController.swift
//  Names 3
//
//  Photos onboarding page: interactive preview of Name Faces experience.
//  Shows a mock carousel of face circles—no photo permission needed for this preview.
//

import UIKit

final class OnboardingPhotosPageViewController: UIViewController {
    
    private let page: OnboardingPage
    let pageIndex: Int
    private let totalPages: Int
    
    private lazy var previewContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 24
        view.layer.cornerCurve = .continuous
        view.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        return view
    }()
    
    private lazy var carouselStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.distribution = .equalSpacing
        return stack
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.textColor = .white
        label.numberOfLines = 0
        return label
    }()
    
    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        label.textAlignment = .center
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.numberOfLines = 0
        return label
    }()
    
    private lazy var mainStackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [previewContainerView, titleLabel, descriptionLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 24
        stack.alignment = .center
        return stack
    }()
    
    init(page: OnboardingPage, pageIndex: Int, totalPages: Int) {
        self.page = page
        self.pageIndex = pageIndex
        self.totalPages = totalPages
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        configureContent()
        buildCarouselPreview()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        animateIn()
    }
    
    private func setupView() {
        view.backgroundColor = page.backgroundColor
        
        view.addSubview(mainStackView)
        previewContainerView.addSubview(carouselStackView)
        
        NSLayoutConstraint.activate([
            previewContainerView.heightAnchor.constraint(equalToConstant: 140),
            previewContainerView.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -64),
            
            carouselStackView.centerXAnchor.constraint(equalTo: previewContainerView.centerXAnchor),
            carouselStackView.centerYAnchor.constraint(equalTo: previewContainerView.centerYAnchor),
            
            mainStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            mainStackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            mainStackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])
        
        mainStackView.setCustomSpacing(20, after: previewContainerView)
        mainStackView.setCustomSpacing(12, after: titleLabel)
    }
    
    private func configureContent() {
        titleLabel.text = page.title
        descriptionLabel.text = page.description
    }
    
    private func buildCarouselPreview() {
        let faceSymbols = ["person.crop.circle.fill", "person.crop.circle.fill", "person.crop.circle.fill", "person.crop.circle.fill", "person.crop.circle.fill"]
        let sizes: [CGFloat] = [44, 56, 72, 56, 44]
        let alphas: [CGFloat] = [0.5, 0.7, 1.0, 0.7, 0.5]
        
        for (index, symbolName) in faceSymbols.enumerated() {
            let circleView = UIView()
            circleView.translatesAutoresizingMaskIntoConstraints = false
            circleView.backgroundColor = page.imageBackgroundColor
            circleView.layer.cornerRadius = sizes[index] / 2
            circleView.layer.cornerCurve = .continuous
            circleView.alpha = alphas[index]
            
            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageView.tintColor = .white
            let config = UIImage.SymbolConfiguration(pointSize: sizes[index] * 0.5, weight: .regular, scale: .medium)
            imageView.image = UIImage(systemName: symbolName, withConfiguration: config)
            imageView.preferredSymbolConfiguration = config
            
            circleView.addSubview(imageView)
            carouselStackView.addArrangedSubview(circleView)
            
            NSLayoutConstraint.activate([
                circleView.widthAnchor.constraint(equalToConstant: sizes[index]),
                circleView.heightAnchor.constraint(equalToConstant: sizes[index]),
                imageView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor)
            ])
        }
    }
    
    private func animateIn() {
        previewContainerView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        previewContainerView.alpha = 0
        titleLabel.alpha = 0
        titleLabel.transform = CGAffineTransform(translationX: 0, y: 16)
        descriptionLabel.alpha = 0
        descriptionLabel.transform = CGAffineTransform(translationX: 0, y: 16)
        
        UIView.animate(withDuration: 0.7, delay: 0.1, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: .curveEaseOut) {
            self.previewContainerView.transform = .identity
            self.previewContainerView.alpha = 1
        }
        
        UIView.animate(withDuration: 0.5, delay: 0.25, options: .curveEaseOut) {
            self.titleLabel.alpha = 1
            self.titleLabel.transform = .identity
        }
        
        UIView.animate(withDuration: 0.5, delay: 0.35, options: .curveEaseOut) {
            self.descriptionLabel.alpha = 1
            self.descriptionLabel.transform = .identity
        }
        
        animateCarouselPulse()
    }
    
    private func animateCarouselPulse() {
        let circles = carouselStackView.arrangedSubviews
        for (index, circle) in circles.enumerated() {
            let delay = Double(index) * 0.08
            UIView.animate(withDuration: 0.4, delay: 0.5 + delay, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.3, options: .curveEaseOut) {
                circle.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
            } completion: { _ in
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    circle.transform = .identity
                }
            }
        }
    }
}
