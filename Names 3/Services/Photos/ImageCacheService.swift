import UIKit
import Photos
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names", category: "ImageCache")

// MARK: - Image Cache Service

final class ImageCacheService {
    static let shared = ImageCacheService()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private let maxMemoryCost = 150 * 1024 * 1024
    
    private init() {
        configureCache()
        observeMemoryWarnings()
        logger.info("ImageCacheService initialized with \(self.maxMemoryCost) bytes limit")
    }
    
    // MARK: - Public API
    
    func image(for identifier: String) -> UIImage? {
        let result = memoryCache.object(forKey: identifier as NSString)
        if result != nil {
            logger.debug("Cache HIT: \(identifier)")
        } else {
            logger.debug("Cache MISS: \(identifier)")
        }
        return result
    }
    
    func setImage(_ image: UIImage, for identifier: String) {
        let cost = estimateCost(for: image)
        memoryCache.setObject(image, forKey: identifier as NSString, cost: cost)
        logger.debug("Cache SET: \(identifier) cost=\(cost) bytes")
    }
    
    func removeImage(for identifier: String) {
        memoryCache.removeObject(forKey: identifier as NSString)
        logger.debug("Cache REMOVE: \(identifier)")
    }
    
    func clearCache() {
        memoryCache.removeAllObjects()
        logger.info("Cache CLEARED")
    }
    
    // MARK: - Private Methods
    
    private func configureCache() {
        memoryCache.totalCostLimit = maxMemoryCost
        memoryCache.countLimit = 1000
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
        logger.warning("Memory warning received, reducing cache")
        let currentCount = memoryCache.countLimit
        memoryCache.countLimit = currentCount / 2
        memoryCache.countLimit = currentCount
    }
    
    private func estimateCost(for image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let bytesPerPixel = 4
        return cgImage.width * cgImage.height * bytesPerPixel
    }
}

// MARK: - Cache Key Generator

enum CacheKeyGenerator {
    static func key(for asset: PHAsset, size: CGSize) -> String {
        "\(asset.localIdentifier)_\(Int(size.width))x\(Int(size.height))"
    }
}