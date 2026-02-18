import UIKit
import Photos

protocol OnboardingViewControllerDelegate: AnyObject {
    func onboardingViewControllerDidFinish(_ controller: OnboardingViewController)
}

private let shouldShowNameFacesAfterOnboardingKey = "Names3.shouldShowNameFacesAfterOnboarding"

final class OnboardingViewController: UIViewController {
    
    weak var delegate: OnboardingViewControllerDelegate?
    
    private let pages = OnboardingPage.pages
    private var currentPageIndex = 0
    
    private lazy var pageViewController: UIPageViewController = {
        let pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        pageVC.dataSource = self
        pageVC.delegate = self
        pageVC.view.translatesAutoresizingMaskIntoConstraints = false
        return pageVC
    }()
    
    private lazy var pageControl: UIPageControl = {
        let pageControl = UIPageControl()
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        pageControl.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.3)
        pageControl.currentPageIndicatorTintColor = .white
        pageControl.isUserInteractionEnabled = false
        return pageControl
    }()
    
    private lazy var continueButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(NSLocalizedString("onboarding.button.continue", comment: "Continue button"), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        button.addTarget(self, action: #selector(continueButtonTapped), for: .touchUpInside)
        button.contentEdgeInsets = UIEdgeInsets(top: 16, left: 32, bottom: 16, right: 32)
        
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        blurView.layer.cornerRadius = 14
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        
        button.insertSubview(blurView, at: 0)
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: button.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        
        return button
    }()
    
    private lazy var skipButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(NSLocalizedString("onboarding.button.skip", comment: "Skip button"), for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .normal)
        button.addTarget(self, action: #selector(skipButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupPageViewController()
        print("🟢 [OnboardingVC] View did load")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("🟢 [OnboardingVC] View did appear")
        updateUI()
    }
    
    private func setupView() {
        view.backgroundColor = pages.first?.backgroundColor ?? .black
        
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)
        
        view.addSubview(containerView)
        containerView.addSubview(pageControl)
        containerView.addSubview(continueButton)
        containerView.addSubview(skipButton)
        
        NSLayoutConstraint.activate([
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            pageControl.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            pageControl.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            
            continueButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            continueButton.topAnchor.constraint(equalTo: pageControl.bottomAnchor, constant: 24),
            continueButton.heightAnchor.constraint(equalToConstant: 50),
            
            skipButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            skipButton.topAnchor.constraint(equalTo: continueButton.bottomAnchor, constant: 12),
            skipButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16)
        ])
    }
    
    private func setupPageViewController() {
        let firstVC = viewController(for: 0)
        pageViewController.setViewControllers([firstVC], direction: .forward, animated: false)
    }
    
    @objc private func continueButtonTapped() {
        print("🔵 [OnboardingVC] Continue tapped, current page: \(currentPageIndex)")
        let currentPage = pages[currentPageIndex]
        
        if currentPage.isPhotosPage {
            requestPhotoPermissionAndContinue()
            return
        }
        
        if currentPageIndex < pages.count - 1 {
            let nextIndex = currentPageIndex + 1
            let nextVC = viewController(for: nextIndex)
            pageViewController.setViewControllers([nextVC], direction: .forward, animated: true) { _ in
                self.currentPageIndex = nextIndex
                self.updateUI()
            }
        } else {
            finishOnboarding()
        }
    }
    
    private func requestPhotoPermissionAndContinue() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            UserDefaults.standard.set(true, forKey: shouldShowNameFacesAfterOnboardingKey)
            finishOnboarding()
            return
        }
        
        if status == .denied || status == .restricted {
            finishOnboarding()
            return
        }
        
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                if newStatus == .authorized || newStatus == .limited {
                    UserDefaults.standard.set(true, forKey: shouldShowNameFacesAfterOnboardingKey)
                }
                self.finishOnboarding()
            }
        }
    }
    
    private func viewController(for index: Int) -> UIViewController {
        let page = pages[index]
        if page.isPhotosPage {
            return OnboardingPhotosPageViewController(
                page: page,
                pageIndex: index,
                totalPages: pages.count
            )
        }
        return OnboardingPageViewController(
            page: page,
            pageIndex: index,
            totalPages: pages.count
        )
    }
    
    @objc private func skipButtonTapped() {
        print("🔵 [OnboardingVC] Skip tapped")
        finishOnboarding()
    }
    
    private func finishOnboarding() {
        print("✅ [OnboardingVC] Finishing onboarding (deferring completeOnboarding until dismiss)")
        delegate?.onboardingViewControllerDidFinish(self)
    }
    
    private func updateUI() {
        pageControl.currentPage = currentPageIndex
        
        let isLastPage = currentPageIndex == pages.count - 1
        let isPhotosPage = pages[currentPageIndex].isPhotosPage
        let buttonTitle: String
        if isPhotosPage {
            buttonTitle = NSLocalizedString("onboarding.button.allowPhotos", comment: "Allow Access to Photos button")
        } else {
            buttonTitle = isLastPage ? NSLocalizedString("onboarding.button.getStarted", comment: "Get Started button") : NSLocalizedString("onboarding.button.continue", comment: "Continue button")
        }
        
        UIView.animate(withDuration: 0.3) {
            self.continueButton.setTitle(buttonTitle, for: .normal)
            self.skipButton.alpha = isLastPage ? 0 : 1
        }
        
        UIView.animate(withDuration: 0.5) {
            self.view.backgroundColor = self.pages[self.currentPageIndex].backgroundColor
        }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
}

extension OnboardingViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        let currentIndex: Int
        if let vc = viewController as? OnboardingPageViewController {
            currentIndex = vc.pageIndex
        } else if let vc = viewController as? OnboardingPhotosPageViewController {
            currentIndex = vc.pageIndex
        } else {
            return nil
        }
        guard currentIndex > 0 else { return nil }
        
        let previousIndex = currentIndex - 1
        return self.viewController(for: previousIndex)
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        let currentIndex: Int
        if let vc = viewController as? OnboardingPageViewController {
            currentIndex = vc.pageIndex
        } else if let vc = viewController as? OnboardingPhotosPageViewController {
            currentIndex = vc.pageIndex
        } else {
            return nil
        }
        guard currentIndex < pages.count - 1 else { return nil }
        
        let nextIndex = currentIndex + 1
        return self.viewController(for: nextIndex)
    }
}

extension OnboardingViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let currentVC = pageViewController.viewControllers?.first else { return }
        if let vc = currentVC as? OnboardingPageViewController {
            currentPageIndex = vc.pageIndex
        } else if let vc = currentVC as? OnboardingPhotosPageViewController {
            currentPageIndex = vc.pageIndex
        } else {
            return
        }
        updateUI()
    }
}