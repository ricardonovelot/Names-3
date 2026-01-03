import Photos
import UIKit

// MARK: - Photo Library Service Protocol

protocol PhotoLibraryServiceProtocol {
    func requestAuthorization() async -> PHAuthorizationStatus
    func fetchAssets(for scope: PhotosPickerScope) -> PHFetchResult<PHAsset>
    func fetchAssets(from startDate: Date, to endDate: Date) -> [PHAsset]
    func requestImage(for asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode) async -> UIImage?
    func observeChanges(handler: @escaping () -> Void) -> PHPhotoLibraryChangeObserver
    func unregisterObserver(_ observer: PHPhotoLibraryChangeObserver)
}

// MARK: - Photo Library Service

final class PhotoLibraryService: PhotoLibraryServiceProtocol {
    static let shared = PhotoLibraryService()
    
    private let imageManager = PHCachingImageManager()
    
    private init() {}
    
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if status == .notDetermined {
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    continuation.resume(returning: newStatus)
                }
            }
        }
        
        return status
    }
    
    func fetchAssets(for scope: PhotosPickerScope) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        switch scope {
        case .day(let date):
            let (start, end) = DateUtility.dayBounds(for: date)
            options.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                start as NSDate,
                end as NSDate
            )
        case .all:
            break
        }
        
        return PHAsset.fetchAssets(with: .image, options: options)
    }
    
    func fetchAssets(from startDate: Date, to endDate: Date) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        
        fetchResult.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        
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
        let observer = PhotoLibraryChangeObserver(onChange: handler)
        PHPhotoLibrary.shared().register(observer)
        return observer
    }
    
    func unregisterObserver(_ observer: PHPhotoLibraryChangeObserver) {
        PHPhotoLibrary.shared().unregisterChangeObserver(observer)
    }
    
    func startCachingImages(for assets: [PHAsset], targetSize: CGSize) {
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }
    
    func stopCachingImagesForAllAssets() {
        imageManager.stopCachingImagesForAllAssets()
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