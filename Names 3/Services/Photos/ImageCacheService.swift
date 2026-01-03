import UIKit
import Photos

// MARK: - Image Cache Service

final class ImageCacheService {
    static let shared = ImageCacheService()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private let maxMemoryCost = 150 * 1024 * 1024 // 150 MB
    
    private init() {
        configureCache()
        observeMemoryWarnings()
    }
    
    // MARK: - Public API
    
    func image(for identifier: String) -> UIImage? {
        memoryCache.object(forKey: identifier as NSString)
    }
    
    func setImage(_ image: UIImage, for identifier: String) {
        let cost = estimateCost(for: image)
        memoryCache.setObject(image, forKey: identifier as NSString, cost: cost)
    }
    
    func removeImage(for identifier: String) {
        memoryCache.removeObject(forKey: identifier as NSString)
    }
    
    func clearCache() {
        memoryCache.removeAllObjects()
    }
    
    // MARK: - Private Methods
    
    private func configureCache() {
        memoryCache.totalCostLimit = maxMemoryCost
        memoryCache.countLimit = 1000 // Max 1000 images
    }
    
    private func observeMemoryWarnings() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }
    
    private func handleMemoryWarning() {
        // Clear 50% of the cache on memory warning
        let currentCount = memoryCache.countLimit
        memoryCache.countLimit = currentCount / 2
        memoryCache.countLimit = currentCount
    }
    
    private func estimateCost(for image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let bytesPerPixel = 4 // RGBA
        return cgImage.width * cgImage.height * bytesPerPixel
    }
}

// MARK: - Cache Key Generator

enum CacheKeyGenerator {
    static func key(for asset: PHAsset, size: CGSize) -> String {
        "\(asset.localIdentifier)_\(Int(size.width))x\(Int(size.height))"
    }
}