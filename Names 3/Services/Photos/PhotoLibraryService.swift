import Photos
import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names", category: "PhotoLibrary")

// MARK: - Photo Library Service Protocol

protocol PhotoLibraryServiceProtocol {
    func requestAuthorization() async -> PHAuthorizationStatus
    func fetchAssets(for scope: PhotosPickerScope) -> PHFetchResult<PHAsset>
    func fetchAssets(from startDate: Date, to endDate: Date) -> [PHAsset]
    func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode) async -> UIImage?
    func observeChanges(handler: @escaping () -> Void) -> PHPhotoLibraryChangeObserver
    func unregisterObserver(_ observer: PHPhotoLibraryChangeObserver)
    func startCachingImages(for assets: [PHAsset], targetSize: CGSize)
    func stopCachingImagesForAllAssets()
    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        resizeMode: PHImageRequestOptionsResizeMode
    ) async throws -> UIImage?
}

// MARK: - Photo Library Service

final class PhotoLibraryService: PhotoLibraryServiceProtocol {
    static let shared = PhotoLibraryService()
    
    private let imageManager = PHCachingImageManager()
    
    private init() {
        logger.info("PhotoLibraryService initialized")
    }
    
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        logger.debug("Current authorization status: \(String(describing: status))")
        
        if status == .notDetermined {
            logger.info("Requesting photo library authorization")
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    logger.info("Authorization result: \(String(describing: newStatus))")
                    continuation.resume(returning: newStatus)
                }
            }
        }
        
        return status
    }
    
    func fetchAssets(for scope: PhotosPickerScope) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        switch scope {
        case .day(let date):
            let (start, end) = DateUtility.dayBounds(for: date)
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                start as NSDate,
                end as NSDate
            )
            logger.debug("Fetching assets for day: \(start) to \(end)")
        case .all:
            logger.debug("Fetching all assets")
            break
        }
        
        return PHAsset.fetchAssets(with: .image, options: options)
    }
    
    func fetchAssets(from startDate: Date, to endDate: Date) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        logger.debug("Fetching assets from \(startDate) to \(endDate)")
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
        logger.debug("Fetched \(assets.count) assets in date range")
        return assets
    }
    
    func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: contentMode,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
    func observeChanges(handler: @escaping () -> Void) -> PHPhotoLibraryChangeObserver {
        logger.info("Registering photo library change observer")
        let observer = PhotoLibraryChangeObserver(onChange: handler)
        PHPhotoLibrary.shared().register(observer)
        return observer
    }
    
    func unregisterObserver(_ observer: PHPhotoLibraryChangeObserver) {
        logger.info("Unregistering photo library change observer")
        PHPhotoLibrary.shared().unregisterChangeObserver(observer)
    }
    
    func startCachingImages(for assets: [PHAsset], targetSize: CGSize) {
        logger.debug("Starting cache for \(assets.count) assets at \(Int(targetSize.width))x\(Int(targetSize.height))")
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: {
                let o = PHImageRequestOptions()
                o.deliveryMode = .opportunistic
                o.resizeMode = .fast
                o.isNetworkAccessAllowed = true
                return o
            }()
        )
    }
    
    func stopCachingImagesForAllAssets() {
        logger.debug("Stopping all image caching")
        imageManager.stopCachingImagesForAllAssets()
    }
    
    func requestImage(
        for asset: PHAsset,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        deliveryMode: PHImageRequestOptionsDeliveryMode,
        resizeMode: PHImageRequestOptionsResizeMode
    ) async throws -> UIImage? {
        var requestID: PHImageRequestID = PHInvalidImageRequestID
        let lock = NSLock()
        var didResume = false
        var continuationRef: CheckedContinuation<UIImage?, Error>?
        
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage?, Error>) in
                continuationRef = continuation
                let options = PHImageRequestOptions()
                options.deliveryMode = deliveryMode
                options.resizeMode = resizeMode
                options.isNetworkAccessAllowed = true
                options.isSynchronous = false
                
                requestID = imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: contentMode,
                    options: options
                ) { image, info in
                    let isCancelled = (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true
                    let error = info?[PHImageErrorKey] as? Error
                    
                    lock.lock()
                    defer { lock.unlock() }
                    if didResume { return }
                    
                    if isCancelled {
                        didResume = true
                        continuation.resume(throwing: CancellationError())
                        continuationRef = nil
                        return
                    }
                    
                    if let error {
                        didResume = true
                        continuation.resume(throwing: error)
                        continuationRef = nil
                        return
                    }
                    
                    if !isDegraded {
                        didResume = true
                        continuation.resume(returning: image)
                        continuationRef = nil
                    }
                }
            }
        }, onCancel: {
            if requestID != PHInvalidImageRequestID {
                self.imageManager.cancelImageRequest(requestID)
            }
            lock.lock()
            defer { lock.unlock() }
            if !didResume {
                didResume = true
                continuationRef?.resume(throwing: CancellationError())
                continuationRef = nil
            }
        })
    }
}

// MARK: - Photo Library Change Observer

final class PhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: () -> Void
    
    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        logger.info("Photo library did change")
        DispatchQueue.main.async {
            self.onChange()
        }
    }
}

// MARK: - Date Utility

enum DateUtility {
    static func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        
        if let interval = calendar.dateInterval(of: .day, for: date) {
            return (interval.start, interval.end)
        }
        
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return (start, end)
    }
}