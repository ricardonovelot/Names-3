import UIKit

protocol OnboardingViewControllerDelegate: AnyObject {
    func onboardingViewControllerDidFinish(_ controller: OnboardingViewController)
}

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
        let firstPage = OnboardingPageViewController(
            page: pages[0],
            pageIndex: 0,
            totalPages: pages.count
        )
        pageViewController.setViewControllers([firstPage], direction: .forward, animated: false)
    }
    
    @objc private func continueButtonTapped() {
        print("🔵 [OnboardingVC] Continue tapped, current page: \(currentPageIndex)")
        if currentPageIndex < pages.count - 1 {
            let nextIndex = currentPageIndex + 1
            let nextPage = OnboardingPageViewController(
                page: pages[nextIndex],
                pageIndex: nextIndex,
                totalPages: pages.count
            )
            
            pageViewController.setViewControllers([nextPage], direction: .forward, animated: true) { _ in
                self.currentPageIndex = nextIndex
                self.updateUI()
            }
        } else {
            finishOnboarding()
        }
    }
    
    @objc private func skipButtonTapped() {
        print("🔵 [OnboardingVC] Skip tapped")
        finishOnboarding()
    }
    
    private func finishOnboarding() {
        print("✅ [OnboardingVC] Finishing onboarding")
        OnboardingManager.shared.completeOnboarding()
        delegate?.onboardingViewControllerDidFinish(self)
    }
    
    private func updateUI() {
        pageControl.currentPage = currentPageIndex
        
        let isLastPage = currentPageIndex == pages.count - 1
        let buttonTitle = isLastPage ? NSLocalizedString("onboarding.button.getStarted", comment: "Get Started button") : NSLocalizedString("onboarding.button.continue", comment: "Continue button")
        
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
        guard let currentVC = viewController as? OnboardingPageViewController,
              currentVC.pageIndex > 0 else {
            return nil
        }
        
        let previousIndex = currentVC.pageIndex - 1
        return OnboardingPageViewController(
            page: pages[previousIndex],
            pageIndex: previousIndex,
            totalPages: pages.count
        )
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let currentVC = viewController as? OnboardingPageViewController,
              currentVC.pageIndex < pages.count - 1 else {
            return nil
        }
        
        let nextIndex = currentVC.pageIndex + 1
        return OnboardingPageViewController(
            page: pages[nextIndex],
            pageIndex: nextIndex,
            totalPages: pages.count
        )
    }
}

extension OnboardingViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed,
              let currentVC = pageViewController.viewControllers?.first as? OnboardingPageViewController else {
            return
        }
        
        currentPageIndex = currentVC.pageIndex
        updateUI()
    }
}