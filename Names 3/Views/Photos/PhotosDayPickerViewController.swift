import UIKit
import SwiftUI
import Photos
import SwiftData

final class PhotosDayPickerViewController: UIViewController {
    
    private let scope: PhotosPickerScope
    private let contactsContext: ModelContext
    private let initialScrollDate: Date?
    private let onPick: (UIImage, Date?) -> Void
    
    private let viewModel: PhotosPickerViewModel
    private let imageManager = PHCachingImageManager()
    
    private var collectionView: UICollectionView!
    private var coordinator: PhotoGridView.Coordinator!
    
    init(scope: PhotosPickerScope, contactsContext: ModelContext, initialScrollDate: Date? = nil, onPick: @escaping (UIImage, Date?) -> Void) {
        self.scope = scope
        self.contactsContext = contactsContext
        self.initialScrollDate = initialScrollDate
        self.onPick = onPick
        self.viewModel = PhotosPickerViewModel(scope: scope, initialScrollDate: initialScrollDate)
        
        super.init(nibName: nil, bundle: nil)
        
        print("🔵 [PhotosDayPickerVC] Initialized")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupNavigationBar()
        setupCollectionView()
        
        viewModel.requestAuthorizationIfNeeded()
        Task {
            await viewModel.reloadForScope(scope)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("✅ [PhotosDayPickerVC] View appeared")
        
        // Check if coordinator is mid-transition before unsuppressing
        if coordinator?.isTransitioning == true {
            print("⏸️ [PhotosDayPickerVC] Coordinator transitioning, deferring reload unsuppression")
            // The coordinator will handle unsuppression after restoration completes
        } else {
            // Re-enable reloads when we come back to the grid (only if not transitioning)
            viewModel.suppressReload(false)
        }
        
        // Always ensure we're observing when visible
        if !viewModel.isObserving {
            print("🔄 [PhotosDayPickerVC] Starting observation")
            viewModel.startObservingChanges()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        print("🔵 [PhotosDayPickerVC] viewWillDisappear - isBeingDismissed: \(isBeingDismissed), isMovingFromParent: \(isMovingFromParent), presentedViewController: \(presentedViewController != nil)")
        
        // Only stop observing if we're actually being dismissed, not if presenting a modal
        if isBeingDismissed || isMovingFromParent {
            print("🔵 [PhotosDayPickerVC] Actually disappearing - stopping observation")
            viewModel.stopObservingChanges()
            viewModel.suppressReload(false)
        } else if presentedViewController != nil {
            // We're presenting a modal (detail view) - suppress reloads but keep observing
            print("🔵 [PhotosDayPickerVC] Presenting modal - suppressing reloads")
            viewModel.suppressReload(true)
        }
    }
    
    private func setupNavigationBar() {
        title = "All Photos"
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark.circle.fill"),
            style: .plain,
            target: self,
            action: #selector(closeButtonTapped)
        )
    }
    
    private func setupCollectionView() {
        view.backgroundColor = .systemGroupedBackground
        
        // Create coordinator
        coordinator = PhotoGridView.Coordinator(
            imageManager: imageManager,
            contactsContext: contactsContext,
            onPhotoTapped: { [weak self] image, date in
                print("✅ [PhotosDayPickerVC] Photo tapped")
                self?.onPick(image, date)
                self?.dismiss(animated: true)
            },
            onAppearAtIndex: { [weak self] index in
                guard let self = self else { return }
                if index < self.viewModel.assets.count {
                    self.viewModel.handlePagination(for: self.viewModel.assets[index])
                }
            },
            onDetailVisibilityChanged: { [weak self] visible in
                print("🔵 [PhotosDayPickerVC] Detail visibility changed: \(visible) -> suppressReload(\(visible))")
                self?.viewModel.suppressReload(visible)
            }
        )
        
        // Create layout and collection view
        let layout = coordinator.makeCompositionalLayout()
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.delegate = coordinator
        collectionView.prefetchDataSource = coordinator
        collectionView.alwaysBounceVertical = true
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseIdentifier)
        
        coordinator.configureDataSource(for: collectionView)
        coordinator.collectionView = collectionView
        
        view.addSubview(collectionView)
        
        // Observe view model changes
        Task { @MainActor in
            for await assets in viewModel.$assets.values {
                print("🔄 [PhotosDayPickerVC] Assets updated: \(assets.count)")
                coordinator.updateAssets(assets, initialScrollDate: initialScrollDate)
            }
        }
    }
    
    @objc private func closeButtonTapped() {
        print("🔵 [PhotosDayPickerVC] Close button tapped")
        dismiss(animated: true)
    }
}

// MARK: - SwiftUI Wrapper

struct PhotosDayPickerViewControllerWrapper: UIViewControllerRepresentable {
    let scope: PhotosPickerScope
    let contactsContext: ModelContext
    let initialScrollDate: Date?
    let onPick: (UIImage, Date?) -> Void
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = PhotosDayPickerViewController(
            scope: scope,
            contactsContext: contactsContext,
            initialScrollDate: initialScrollDate,
            onPick: onPick
        )
        let nav = UINavigationController(rootViewController: vc)
        return nav
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // No updates needed
    }
}