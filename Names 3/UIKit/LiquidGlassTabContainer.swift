import SwiftUI
import UIKit

extension Notification.Name {
    static let quickInputRequested = Notification.Name("quickInputRequested")
}

struct LiquidGlassTabContainer: UIViewControllerRepresentable {
    let people: () -> AnyView
    let notes: () -> AnyView
    let explore: () -> AnyView
    let accessorySystemImage: String
    let accessoryTapped: () -> Void

    func makeUIViewController(context: Context) -> GlassTabBarController {
        let tab = GlassTabBarController(accessorySystemImage: accessorySystemImage) {
            accessoryTapped()
        }

        // Build the three SwiftUI tabs wrapped in UIHostingController.
        let peopleVC = UIHostingController(rootView: people())
        peopleVC.tabBarItem = UITabBarItem(title: "People", image: UIImage(systemName: "person.3"), selectedImage: nil)

        let notesVC = UIHostingController(rootView: notes())
        notesVC.tabBarItem = UITabBarItem(title: "Notes", image: UIImage(systemName: "note.text"), selectedImage: nil)

        let exploreVC = UIHostingController(rootView: explore())
        exploreVC.tabBarItem = UITabBarItem(title: "Explore", image: UIImage(systemName: "camera.macro"), selectedImage: nil)

        tab.viewControllers = [peopleVC, notesVC, exploreVC]
        tab.selectedIndex = 0

        return tab
    }

    func updateUIViewController(_ uiViewController: GlassTabBarController, context: Context) {
        // No-op; the controller manages its own layout.
    }
}

final class GlassTabBarController: UITabBarController {
    private let accessoryAction: () -> Void
    private let accessorySystemImage: String

    private let accessoryContainer = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let accessoryButton = UIButton(type: .system)

    init(accessorySystemImage: String, action: @escaping () -> Void) {
        self.accessorySystemImage = accessorySystemImage
        self.accessoryAction = action
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Tab bar appearance: translucent, floating style.
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor.clear
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.layer.masksToBounds = false

        // Accessory container
        accessoryContainer.translatesAutoresizingMaskIntoConstraints = false
        accessoryContainer.clipsToBounds = true
        accessoryContainer.layer.cornerCurve = .continuous
        accessoryContainer.layer.cornerRadius = 26
        accessoryContainer.layer.shadowColor = UIColor.black.cgColor
        accessoryContainer.layer.shadowOpacity = 0.15
        accessoryContainer.layer.shadowRadius = 10
        accessoryContainer.layer.shadowOffset = CGSize(width: 0, height: 4)

        // Button
        accessoryButton.translatesAutoresizingMaskIntoConstraints = false
        accessoryButton.tintColor = .white
        accessoryButton.setImage(UIImage(systemName: accessorySystemImage), for: .normal)
        accessoryButton.addTarget(self, action: #selector(accessoryTapped), for: .touchUpInside)

        accessoryContainer.contentView.addSubview(accessoryButton)
        NSLayoutConstraint.activate([
            accessoryButton.centerXAnchor.constraint(equalTo: accessoryContainer.contentView.centerXAnchor),
            accessoryButton.centerYAnchor.constraint(equalTo: accessoryContainer.contentView.centerYAnchor)
        ])

        view.addSubview(accessoryContainer)

        // Layout
        NSLayoutConstraint.activate([
            accessoryContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            accessoryContainer.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -10),
            accessoryContainer.widthAnchor.constraint(equalToConstant: 52),
            accessoryContainer.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    @objc private func accessoryTapped() {
        // Switch to People tab before notifying (mirrors Apple's context switch to Search)
        selectedIndex = 0
        accessoryAction()
        NotificationCenter.default.post(name: .quickInputRequested, object: nil)
    }
}