import UIKit

final class OnboardingPageViewController: UIViewController {
    
    private let page: OnboardingPage
    let pageIndex: Int
    private let totalPages: Int
    
    private lazy var imageContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 80
        view.layer.cornerCurve = .continuous
        return view
    }()
    
    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        let config = UIImage.SymbolConfiguration(pointSize: 80, weight: .regular, scale: .large)
        imageView.preferredSymbolConfiguration = config
        return imageView
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 34, weight: .bold)
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
        label.textColor = UIColor.white.withAlphaComponent(0.8)
        label.numberOfLines = 0
        return label
    }()
    
    private lazy var stackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [imageContainerView, titleLabel, descriptionLabel])
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
    }
    
    private func setupView() {
        view.backgroundColor = page.backgroundColor
        
        view.addSubview(stackView)
        imageContainerView.addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageContainerView.widthAnchor.constraint(equalToConstant: 160),
            imageContainerView.heightAnchor.constraint(equalToConstant: 160),
            
            imageView.centerXAnchor.constraint(equalTo: imageContainerView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageContainerView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 80),
            imageView.heightAnchor.constraint(equalToConstant: 80),
            
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            stackView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])
        
        stackView.setCustomSpacing(32, after: imageContainerView)
        stackView.setCustomSpacing(16, after: titleLabel)
    }
    
    private func configureContent() {
        imageContainerView.backgroundColor = page.imageBackgroundColor
        imageView.image = UIImage(systemName: page.imageName)
        titleLabel.text = page.title
        descriptionLabel.text = page.description
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        animateIn()
    }
    
    private func animateIn() {
        imageContainerView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        imageContainerView.alpha = 0
        titleLabel.alpha = 0
        titleLabel.transform = CGAffineTransform(translationX: 0, y: 20)
        descriptionLabel.alpha = 0
        descriptionLabel.transform = CGAffineTransform(translationX: 0, y: 20)
        
        UIView.animate(withDuration: 0.6, delay: 0.1, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: .curveEaseOut) {
            self.imageContainerView.transform = .identity
            self.imageContainerView.alpha = 1
        }
        
        UIView.animate(withDuration: 0.5, delay: 0.3, options: .curveEaseOut) {
            self.titleLabel.alpha = 1
            self.titleLabel.transform = .identity
        }
        
        UIView.animate(withDuration: 0.5, delay: 0.4, options: .curveEaseOut) {
            self.descriptionLabel.alpha = 1
            self.descriptionLabel.transform = .identity
        }
    }
}
