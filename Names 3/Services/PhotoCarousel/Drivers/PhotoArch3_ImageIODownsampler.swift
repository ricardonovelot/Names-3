//
//  PhotoArch3_ImageIODownsampler.swift
//  Names 3
//
//  Architecture 3: ImageIO Downsampler
//
//  Philosophy: Never allocate a full-resolution bitmap in memory. Instead, use
//  CGImageSourceCreateThumbnailAtIndex to downsample directly from the encoded
//  JPEG/HEIC data on disk to the exact display pixel size. This is Apple's
//  recommended technique from WWDC 2018 "Image and Graphics Best Practices."
//
//  The approach has three tiers:
//   1. EXIF thumbnail: extracted from photo metadata in ~1ms, ~160px, free
//   2. Downsampled preview: CGImageSource at 1/4 display size (~300-400px), fast
//   3. Display-quality: CGImageSource at exact display pixel size, final
//
//  Memory footprint is minimal because we never hold the original 12MP+ photo
//  as a decoded bitmap. Each tier overwrites the previous in the same UIImageView.
//  PHImageManager.requestImageDataAndOrientation gives us the raw encoded bytes
//  which we feed directly to CGImageSource.
//

import UIKit
import Photos
import ImageIO

// MARK: - ImageIO Thumbnail Extractor

private enum ImageIOExtractor {
    private static let queue = DispatchQueue(label: "com.names3.imageIO.downsample", qos: .userInitiated, attributes: .concurrent)

    struct DownsampleResult {
        let image: UIImage
        let tier: Tier
    }

    enum Tier {
        case exifThumb
        case preview
        case display
    }

    static func downsample(data: Data, orientation: CGImagePropertyOrientation, maxPixelSize: CGFloat, tier: Tier) async -> DownsampleResult? {
        await withCheckedContinuation { cont in
            queue.async {
                let result = downsampleSync(data: data, orientation: orientation, maxPixelSize: maxPixelSize, tier: tier)
                cont.resume(returning: result)
            }
        }
    }

    static func exifThumbnail(data: Data, orientation: CGImagePropertyOrientation) async -> DownsampleResult? {
        await withCheckedContinuation { cont in
            queue.async {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    cont.resume(returning: nil)
                    return
                }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                    kCGImageSourceCreateThumbnailFromImageAlways: false,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    cont.resume(returning: nil)
                    return
                }
                let uiImage = UIImage(cgImage: cgThumb, scale: 1.0, orientation: uiOrientation(from: orientation))
                cont.resume(returning: DownsampleResult(image: uiImage, tier: .exifThumb))
            }
        }
    }

    private static func downsampleSync(data: Data, orientation: CGImagePropertyOrientation, maxPixelSize: CGFloat, tier: Tier) -> DownsampleResult? {
        if let mb = ProcessMemoryReporter.currentMegabytes(), mb > 380 { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let uiImage = UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
        return DownsampleResult(image: uiImage, tier: tier)
    }

    private static func uiOrientation(from cg: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch cg {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        }
    }
}

// MARK: - Data Fetcher

private actor ImageDataFetcher {
    private let manager = PHImageManager.default()
    private var dataCache: [String: (Data, CGImagePropertyOrientation)] = [:]
    private let maxDataCacheCount = 30

    func fetchImageData(for asset: PHAsset) async -> (Data, CGImagePropertyOrientation)? {
        if let cached = dataCache[asset.localIdentifier] { return cached }

        let result: (Data, CGImagePropertyOrientation)? = await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
            opts.isSynchronous = false
            manager.requestImageDataAndOrientation(for: asset, options: opts) { data, _, orientation, info in
                StorageMonitor.reportIfCloudPhotoLowStorage(info: info)
                if let data {
                    cont.resume(returning: (data, orientation))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }

        if let result {
            if dataCache.count >= maxDataCacheCount {
                let keysToRemove = Array(dataCache.keys.prefix(10))
                for k in keysToRemove { dataCache.removeValue(forKey: k) }
            }
            dataCache[asset.localIdentifier] = result
        }

        return result
    }

    func evictAll() {
        dataCache.removeAll()
    }
}

// MARK: - Tier Cache

@MainActor
private final class TierCache {
    private let cache = NSCache<NSString, UIImage>()
    private let maxCostBytes: Int

    init(maxMB: Int) {
        maxCostBytes = maxMB * 1024 * 1024
        cache.totalCostLimit = maxCostBytes
        cache.countLimit = 200

        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    func get(_ key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func set(_ image: UIImage, key: String) {
        let cost = (image.cgImage.map { $0.width * $0.height * 4 }) ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}

// MARK: - Driver

@MainActor
final class PhotoArch3_ImageIODownsamplerDriver: PhotoCarouselDriver {
    static let shared = PhotoArch3_ImageIODownsamplerDriver()

    private let displayCache = TierCache(maxMB: 60)
    private let previewCache = TierCache(maxMB: 15)
    private let exifCache = TierCache(maxMB: 5)
    private let dataFetcher = ImageDataFetcher()
    private let cachingManager = PHCachingImageManager()
    private var warmupTasks: [Int: Task<Void, Never>] = [:]

    private init() {}

    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let displayKey = CacheKeyGenerator.key(for: asset, size: targetSize)
        if let display = displayCache.get(displayKey) { return display }

        let previewKey = "\(asset.localIdentifier)_preview"
        if let preview = previewCache.get(previewKey) {
            Task { await self.loadTier3(asset: asset, targetSize: targetSize, displayKey: displayKey) }
            return preview
        }

        let exifKey = "\(asset.localIdentifier)_exif"
        if let exif = exifCache.get(exifKey) {
            Task { await self.loadAllTiers(asset: asset, targetSize: targetSize, displayKey: displayKey, previewKey: previewKey) }
            return exif
        }

        guard let (data, orientation) = await dataFetcher.fetchImageData(for: asset) else {
            return await fallbackPHLoad(asset: asset, targetSize: targetSize)
        }

        let maxDimension = max(targetSize.width, targetSize.height)

        if let exifResult = await ImageIOExtractor.exifThumbnail(data: data, orientation: orientation) {
            exifCache.set(exifResult.image, key: exifKey)
        }

        let previewPixels = max(300, maxDimension / 3)
        if let previewResult = await ImageIOExtractor.downsample(data: data, orientation: orientation, maxPixelSize: previewPixels, tier: .preview) {
            previewCache.set(previewResult.image, key: previewKey)
        }

        if let displayResult = await ImageIOExtractor.downsample(data: data, orientation: orientation, maxPixelSize: maxDimension, tier: .display) {
            displayCache.set(displayResult.image, key: displayKey)
            return displayResult.image
        }

        return previewCache.get(previewKey) ?? exifCache.get(exifKey)
    }

    func preheat(assets: [PHAsset], targetSize: CGSize) {
        for asset in assets.prefix(6) {
            let displayKey = CacheKeyGenerator.key(for: asset, size: targetSize)
            guard displayCache.get(displayKey) == nil else { continue }
            Task {
                guard let (data, orientation) = await self.dataFetcher.fetchImageData(for: asset) else { return }
                guard !Task.isCancelled else { return }
                let maxDim = max(targetSize.width, targetSize.height)
                if let result = await ImageIOExtractor.downsample(data: data, orientation: orientation, maxPixelSize: maxDim, tier: .display) {
                    self.displayCache.set(result.image, key: displayKey)
                }
            }
        }
    }

    func prefetchIndices(currentPage: Int, totalCount: Int) -> [Int] {
        let lo = max(0, currentPage - 2)
        let hi = min(totalCount - 1, currentPage + 2)
        guard lo <= hi else { return [] }
        return (lo...hi).filter { $0 != currentPage }
    }

    func onCarouselAppeared(assets: [PHAsset], viewportSize: CGSize) {
        let displaySize = PhotoDisplayHelpers.displayTargetSize(for: viewportSize)
        let maxDim = max(displaySize.width, displaySize.height)

        for (i, asset) in assets.prefix(8).enumerated() {
            let displayKey = CacheKeyGenerator.key(for: asset, size: displaySize)
            guard displayCache.get(displayKey) == nil else { continue }

            let task = Task {
                guard let (data, orientation) = await self.dataFetcher.fetchImageData(for: asset) else { return }
                guard !Task.isCancelled else { return }

                let previewKey = "\(asset.localIdentifier)_preview"
                let previewPixels = max(300, maxDim / 3)
                if self.previewCache.get(previewKey) == nil,
                   let previewResult = await ImageIOExtractor.downsample(data: data, orientation: orientation, maxPixelSize: previewPixels, tier: .preview) {
                    self.previewCache.set(previewResult.image, key: previewKey)
                }

                guard !Task.isCancelled else { return }

                if let displayResult = await ImageIOExtractor.downsample(data: data, orientation: orientation, maxPixelSize: maxDim, tier: .display) {
                    self.displayCache.set(displayResult.image, key: displayKey)
                }
            }
            warmupTasks[i] = task
        }
    }

    func onCarouselDisappeared() {
        warmupTasks.values.forEach { $0.cancel() }
        warmupTasks.removeAll()
    }

    func cancelLoad(at index: Int) {
        warmupTasks[index]?.cancel()
        warmupTasks.removeValue(forKey: index)
    }

    // MARK: - Private

    private func loadTier3(asset: PHAsset, targetSize: CGSize, displayKey: String) async {
        guard displayCache.get(displayKey) == nil else { return }
        guard let (data, orientation) = await dataFetcher.fetchImageData(for: asset) else { return }
        let maxDim = max(targetSize.width, targetSize.height)
        if let result = await ImageIOExtractor.downsample(data: data, orientation: orientation, maxPixelSize: maxDim, tier: .display) {
            displayCache.set(result.image, key: displayKey)
        }
    }

    private func loadAllTiers(asset: PHAsset, targetSize: CGSize, displayKey: String, previewKey: String) async {
        guard let (data, orientation) = await dataFetcher.fetchImageData(for: asset) else { return }
        let maxDim = max(targetSize.width, targetSize.height)

        let previewPixels = max(300, maxDim / 3)
        if previewCache.get(previewKey) == nil,
           let previewResult = await ImageIOExtractor.downsample(data: data, orientation: orientation, maxPixelSize: previewPixels, tier: .preview) {
            previewCache.set(previewResult.image, key: previewKey)
        }

        if displayCache.get(displayKey) == nil,
           let displayResult = await ImageIOExtractor.downsample(data: data, orientation: orientation, maxPixelSize: maxDim, tier: .display) {
            displayCache.set(displayResult.image, key: displayKey)
        }
    }

    private func fallbackPHLoad(asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = .exact
            opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: opts) { image, info in
                StorageMonitor.reportIfCloudPhotoLowStorage(info: info)
                cont.resume(returning: image)
            }
        }
    }
}
