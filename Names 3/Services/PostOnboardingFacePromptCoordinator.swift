import UIKit
import SwiftData
import Photos
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names", category: "PostOnboardingPrompt")

final class PostOnboardingFacePromptCoordinator {
    private weak var window: UIWindow?
    private var welcomeViewController: WelcomeFaceNamingViewController?
    private let modelContext: ModelContext
    private var completion: (() -> Void)?
    
    init(window: UIWindow?, modelContext: ModelContext) {
        self.window = window
        self.modelContext = modelContext
        logger.info("PostOnboardingFacePromptCoordinator initialized")
    }
    
    deinit {
        logger.info("PostOnboardingFacePromptCoordinator deinitialized")
    }
    
    func start(forced: Bool = false, completion: (() -> Void)? = nil) {
        self.completion = completion
        logger.info("Starting post-onboarding face prompt (forced: \(forced))")
        
        Task { @MainActor in
            if !forced && !shouldShowPrompt() {
                logger.info("Skipping face prompt - user already has contacts")
                completion?()
                return
            }
            
            let status = await PhotoLibraryService.shared.requestAuthorization()
            guard status == .authorized || status == .limited else {
                logger.warning("Photo library access denied, skipping face prompt")
                completion?()
                return
            }
            
            await presentWelcomeView()
        }
    }
    
    private func shouldShowPrompt() -> Bool {
        let descriptor = FetchDescriptor<Contact>(predicate: #Predicate { contact in
            contact.isArchived == false
        })
        
        do {
            let contacts = try modelContext.fetch(descriptor)
            let shouldShow = contacts.isEmpty
            logger.info("Should show prompt: \(shouldShow) (contacts count: \(contacts.count))")
            return shouldShow
        } catch {
            logger.error("Failed to fetch contacts: \(error)")
            return false
        }
    }
    
    @MainActor
    private func presentWelcomeView() async {
        guard let window = self.window else {
            logger.error("No window available")
            completion?()
            return
        }
        
        logger.info("Fetching smart photo selection...")
        
        let smartAssets = fetchSmartPhotoSelection()
        
        guard smartAssets.count > 0 else {
            logger.info("No relevant photos found")
            completion?()
            return
        }
        
        logger.info("Selected \(smartAssets.count) high-priority photos for face detection")
        
        let welcomeVC = WelcomeFaceNamingViewController(
            prioritizedAssets: smartAssets,
            modelContext: modelContext
        )
        welcomeVC.delegate = self
        welcomeVC.modalPresentationStyle = .fullScreen
        welcomeVC.modalTransitionStyle = .crossDissolve
        self.welcomeViewController = welcomeVC
        
        guard let rootVC = window.rootViewController else {
            logger.error("No root view controller")
            completion?()
            return
        }
        
        let presenter = findTopMostViewController(rootVC)
        
        if presenter.presentedViewController != nil {
            logger.info("Presenter already presenting, waiting...")
            try? await Task.sleep(for: .seconds(1))
        }
        
        logger.info("Presenting welcome face naming view")
        presenter.present(welcomeVC, animated: true) {
            logger.info("Welcome view presentation completed")
        }
    }
    
    private func fetchSmartPhotoSelection() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue),
            NSPredicate(format: "(mediaSubtype & %d) == 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
        ])
        
        let fetchResult = PHAsset.fetchAssets(with: options)
        
        // Time-based clustering to avoid photos from the same moment
        // Skip photos taken within this many seconds of the last selected photo
        let minimumTimeGapSeconds: TimeInterval = 300 // 5 minutes
        
        var selectedAssets: [PHAsset] = []
        var lastSelectedDate: Date?
        
        fetchResult.enumerateObjects { asset, _, _ in
            guard let creationDate = asset.creationDate else { return }
            
            // Check if this photo is far enough in time from the last selected photo
            if let lastDate = lastSelectedDate {
                let timeDifference = abs(lastDate.timeIntervalSince(creationDate))
                if timeDifference < minimumTimeGapSeconds {
                    // Skip this photo - it's too close in time to the previous one
                    return
                }
            }
            
            // This photo passes the time filter
            selectedAssets.append(asset)
            lastSelectedDate = creationDate
        }
        
        logger.info("Smart selection: filtered \(fetchResult.count) photos → \(selectedAssets.count) time-diverse photos (min gap: \(Int(minimumTimeGapSeconds/60)) minutes)")
        
        return selectedAssets
    }
    
    private func findTopMostViewController(_ controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return findTopMostViewController(presented)
        }
        
        if let nav = controller as? UINavigationController,
           let visible = nav.visibleViewController {
            return findTopMostViewController(visible)
        }
        
        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController {
            return findTopMostViewController(selected)
        }
        
        return controller
    }
    
    func dismiss() {
        logger.info("Dismissing welcome face naming view")
        welcomeViewController?.dismiss(animated: true) { [weak self] in
            logger.info("Welcome view dismissed")
            self?.welcomeViewController = nil
            self?.completion?()
            self?.completion = nil
        }
    }
}

extension PostOnboardingFacePromptCoordinator: WelcomeFaceNamingViewControllerDelegate {
    func welcomeFaceNamingViewControllerDidFinish(_ controller: WelcomeFaceNamingViewController) {
        logger.info("User finished or skipped welcome face naming")
        dismiss()
    }
}

import Vision