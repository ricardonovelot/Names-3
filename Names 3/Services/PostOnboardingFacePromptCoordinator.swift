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
    
    func start(completion: (() -> Void)? = nil) {
        self.completion = completion
        logger.info("Starting post-onboarding face prompt")
        
        Task { @MainActor in
            guard shouldShowPrompt() else {
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
        
        logger.info("Fetching recent photos with faces...")
        
        guard let photosWithFaces = await fetchRecentPhotosWithFaces(limit: 10) else {
            logger.info("No recent photos with faces found")
            completion?()
            return
        }
        
        guard !photosWithFaces.isEmpty else {
            logger.info("No photos with detected faces")
            completion?()
            return
        }
        
        logger.info("Found \(photosWithFaces.count) photos with faces, presenting welcome view")
        
        let welcomeVC = WelcomeFaceNamingViewController(
            photosWithFaces: photosWithFaces,
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
    
    private func fetchRecentPhotosWithFaces(limit: Int) async -> [(image: UIImage, date: Date, asset: PHAsset)]? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 50
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let fetchResult = PHAsset.fetchAssets(with: options)
        var photosWithFaces: [(image: UIImage, date: Date, asset: PHAsset)] = []
        var checked = 0
        
        for index in 0..<fetchResult.count {
            guard photosWithFaces.count < limit else { break }
            guard checked < 50 else { break }
            
            let asset = fetchResult.object(at: index)
            checked += 1
            
            guard let image = await loadFullImage(for: asset) else {
                continue
            }
            
            let hasFaces = await detectFaces(in: image)
            
            if hasFaces {
                let date = asset.creationDate ?? Date()
                photosWithFaces.append((image: image, date: date, asset: asset))
                logger.debug("Found photo with faces from \(date)")
            }
        }
        
        return photosWithFaces.isEmpty ? nil : photosWithFaces
    }
    
    private func loadFullImage(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        return await withCheckedContinuation { continuation in
            PHCachingImageManager().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    private func detectFaces(in image: UIImage) async -> Bool {
        guard let cgImage = image.cgImage else { return false }
        
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
                let faces = (request.results as? [VNFaceObservation]) ?? []
                continuation.resume(returning: !faces.isEmpty)
            } catch {
                continuation.resume(returning: false)
            }
        }
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