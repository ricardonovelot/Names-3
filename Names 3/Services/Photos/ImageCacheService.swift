import UIKit
import Photos
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names", category: "ImageCache")

// MARK: - Image Cache Service

final class ImageCacheService {
    static let shared = ImageCacheService()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    /// Conservative limit for iOS: ~50MB to avoid process kill (device has limited headroom).
    private let maxMemoryCost = 50 * 1024 * 1024
    
    private init() {
        configureCache()
        observeMemoryWarnings()
        logger.info("ImageCacheService initialized with \(self.maxMemoryCost / 1024 / 1024)MB limit")
        ProcessReportCoordinator.shared.register(name: "ImageCacheService") { [weak self] in
            guard let self else {
                return ProcessReportSnapshot(name: "ImageCacheService", payload: ["state": "released"])
            }
            return ProcessReportSnapshot(
                name: "ImageCacheService",
                payload: [
                    "costLimitMB": "\(self.maxMemoryCost / 1024 / 1024)",
                    "countLimit": "\(self.memoryCache.countLimit)",
                    "totalCostLimit": "\(self.memoryCache.totalCostLimit)"
                ]
            )
        }
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
        logger.info("Cache cleared")
    }
    
    // MARK: - Private Methods
    
    private func configureCache() {
        memoryCache.totalCostLimit = maxMemoryCost
        memoryCache.countLimit = 200
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
        // #region agent log
        debugSessionLog(location: "ImageCacheService:handleMemoryWarning", message: "Memory warning reducing cache", data: ["entered": 1], hypothesisId: "H3")
        // #endregion
        logger.warning("Memory warning received, clearing image cache")
        memoryCache.totalCostLimit = maxMemoryCost / 2
        memoryCache.countLimit = 50
        memoryCache.removeAllObjects()
    }
    
    private func estimateCost(for image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let bytesPerPixel = 4
        return cgImage.width * cgImage.height * bytesPerPixel
    }
}

// MARK: - Cache Key Generator

enum CacheKeyGenerator {
    /// Generate a cache key that includes pixel size and screen scale to avoid serving undersized images.
    static func key(for asset: PHAsset, size: CGSize) -> String {
        // Treat `size` as pixel size; include it directly, and include scale for safety if `size` was computed in points.
        let scale = Int(UIScreen.main.scale)
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())
        return "\(asset.localIdentifier)_\(w)x\(h)@\(scale)x"
    }
}
