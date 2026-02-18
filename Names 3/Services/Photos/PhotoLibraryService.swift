import Photos
import UIKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names", category: "PhotoLibrary")

/// Posted when the Photos daemon disconnects (e.g. after memory pressure). Observe to dismiss photo-heavy UI and avoid touching PHAsset/PHFetchResult.
extension Notification.Name {
    static let photoLibraryDidBecomeUnavailable = Notification.Name("PhotoLibraryDidBecomeUnavailable")
}

/// Thrown when the photo library is no longer available (e.g. photolibraryd exited).
struct PhotoLibraryUnavailableError: Error {}

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
    private let availabilityLock = NSLock()
    private var _libraryUnavailable = false
    
    private init() {
        logger.info("PhotoLibraryService initialized")
        ProcessReportCoordinator.shared.register(name: "PhotoLibraryService") { [weak self] in
            guard let self else {
                return ProcessReportSnapshot(name: "PhotoLibraryService", payload: ["state": "released"])
            }
            let unavailable = self.isPhotoLibraryAvailable() ? "no" : "yes"
            return ProcessReportSnapshot(
                name: "PhotoLibraryService",
                payload: ["state": "active", "cachingImageManager": "yes", "libraryUnavailable": unavailable]
            )
        }
        observeBecomeActive()
    }
    
    /// True until an image request (or other PH call) fails with an error, e.g. after photolibraryd exits. Cleared on didBecomeActive.
    func isPhotoLibraryAvailable() -> Bool {
        availabilityLock.lock()
        defer { availabilityLock.unlock() }
        return !_libraryUnavailable
    }
    
    private func setLibraryUnavailable() {
        availabilityLock.lock()
        let wasAvailable = !_libraryUnavailable
        _libraryUnavailable = true
        availabilityLock.unlock()
        if wasAvailable {
            logger.warning("Photo library marked unavailable (daemon disconnect / error)")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .photoLibraryDidBecomeUnavailable, object: self)
            }
        }
    }
    
    private func observeBecomeActive() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.availabilityLock.lock()
            self?._libraryUnavailable = false
            self?.availabilityLock.unlock()
        }
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

    /// Fetches image assets in date range, excluding screenshots (for calendar thumbnails).
    func fetchAssetsExcludingScreenshots(from startDate: Date, to endDate: Date) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let screenshotRaw = PHAssetMediaSubtype.photoScreenshot.rawValue
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "creationDate >= %@ AND creationDate < %@", startDate as NSDate, endDate as NSDate),
            NSPredicate(format: "(mediaSubtype & %d) == 0", screenshotRaw)
        ])
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        logger.debug("Fetched \(assets.count) assets (excluding screenshots) in date range")
        return assets
    }

    /// Result of loading calendar month: one thumbnail per day and photo count per day (for layout).
    struct CalendarMonthResult {
        var thumbnails: [Date: Data]
        var photoCountByDay: [Date: Int]
    }

    /// Loads one thumbnail per day for the given month (for calendar UI). Returns thumbnails and photo count per day.
    /// Picks a relevant asset per day (prefer favorites, skip extreme aspect ratios and tiny images). Uses high-quality delivery.
    func loadThumbnailsForCalendarMonth(
        monthStart: Date,
        targetSize: CGSize = CGSize(width: 320, height: 320)
    ) async -> CalendarMonthResult {
        let calendar = Calendar.current
        let (start, end) = DateUtility.monthBounds(containing: monthStart)
        let assets = fetchAssetsExcludingScreenshots(from: start, to: end)
        guard !assets.isEmpty else { return CalendarMonthResult(thumbnails: [:], photoCountByDay: [:]) }
        let screenshotRaw = PHAssetMediaSubtype.photoScreenshot.rawValue
        var assetsByDay: [Date: [PHAsset]] = [:]
        for asset in assets {
            guard let creationDate = asset.creationDate else { continue }
            if (asset.mediaSubtypes.rawValue & screenshotRaw) != 0 { continue }
            let dayStart = calendar.startOfDay(for: creationDate)
            assetsByDay[dayStart, default: []].append(asset)
        }
        var photoCountByDay: [Date: Int] = [:]
        for (dayStart, dayAssets) in assetsByDay {
            photoCountByDay[dayStart] = dayAssets.count
        }
        var firstAssetByDay: [Date: PHAsset] = [:]
        for (dayStart, dayAssets) in assetsByDay {
            if let best = bestCalendarAsset(from: dayAssets) {
                firstAssetByDay[dayStart] = best
            }
        }
        let items = Array(firstAssetByDay)
        let batchSize = 6
        var thumbnails: [Date: Data] = [:]
        for chunkStart in stride(from: 0, to: items.count, by: batchSize) {
            let batch = Array(items[chunkStart..<min(chunkStart + batchSize, items.count)])
            await withTaskGroup(of: (Date, Data?).self) { group in
                for (dayStart, asset) in batch {
                    group.addTask {
                        guard let image = try? await self.requestImage(
                            for: asset,
                            targetSize: targetSize,
                            contentMode: .aspectFill,
                            deliveryMode: .highQualityFormat,
                            resizeMode: .fast
                        ) else { return (dayStart, nil) }
                        let data = image.jpegData(compressionQuality: 0.9)
                        return (dayStart, data)
                    }
                }
                for await (dayStart, data) in group {
                    if let data = data {
                        thumbnails[dayStart] = data
                    }
                }
            }
        }
        return CalendarMonthResult(thumbnails: thumbnails, photoCountByDay: photoCountByDay)
    }

    /// Picks the most relevant asset for a calendar day: prefer favorites, skip screenshots, skip extreme aspect ratios, skip small images.
    private func bestCalendarAsset(from assets: [PHAsset]) -> PHAsset? {
        let screenshotRaw = PHAssetMediaSubtype.photoScreenshot.rawValue
        let nonScreenshots = assets.filter { (($0.mediaSubtypes.rawValue & screenshotRaw) == 0) }
        let candidates = nonScreenshots.isEmpty ? assets : nonScreenshots
        let minShortSide: Int = 500
        let minAspectRatio: CGFloat = 0.58
        let maxAspectRatio: CGFloat = 1.85
        func isReasonable(_ asset: PHAsset) -> Bool {
            let w = asset.pixelWidth
            let h = asset.pixelHeight
            guard w > 0, h > 0 else { return false }
            if min(w, h) < minShortSide { return false }
            let ratio = CGFloat(min(w, h)) / CGFloat(max(w, h))
            return ratio >= minAspectRatio && ratio <= maxAspectRatio
        }
        let reasonable = candidates.filter(isReasonable)
        let pool = reasonable.isEmpty ? candidates : reasonable
        if pool.isEmpty { return nil }
        let favorite = pool.first(where: { $0.isFavorite })
        return favorite ?? pool.first
    }

    func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode) async -> UIImage? {
        guard isPhotoLibraryAvailable() else { return nil }
        return await withCheckedContinuation { continuation in
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
            ) { [weak self] image, info in
                if info?[PHImageErrorKey] != nil {
                    self?.setLibraryUnavailable()
                }
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
        guard isPhotoLibraryAvailable() else { return }
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
        guard isPhotoLibraryAvailable() else { throw PhotoLibraryUnavailableError() }
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
                        self.setLibraryUnavailable()
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
    private static var changeCount = 0
    
    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard PhotoLibraryService.shared.isPhotoLibraryAvailable() else { return }
        // #region agent log
        Self.changeCount += 1
        debugSessionLog(location: "PhotoLibraryService:photoLibraryDidChange", message: "Photo library did change", data: ["changeCount": Self.changeCount], hypothesisId: "H1")
        // #endregion
        logger.info("Photo library did change")
        DispatchQueue.main.async {
            guard PhotoLibraryService.shared.isPhotoLibraryAvailable() else { return }
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

    /// Start and end (exclusive) of the calendar month containing the given date.
    static func monthBounds(containing date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: date) else {
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            return (start, end)
        }
        return (interval.start, interval.end)
    }
}