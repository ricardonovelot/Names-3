//
//  PhotoArch4_CoreImageGPU.swift
//  Names 3
//
//  Architecture 4: Core Image GPU Pipeline
//
//  Philosophy: Leverage the GPU for all image processing. CIImage objects are lazy —
//  they represent a recipe, not a bitmap. No intermediate CPU bitmaps are allocated
//  until the final render. CIContext backed by Metal performs the resize, color
//  management, and format conversion on the GPU in a single pass.
//
//  Key advantages:
//  - GPU-side resize: the 12MP HEIC is decoded and resized to display size entirely
//    on the GPU. The CPU never sees the full-resolution pixels.
//  - Metal texture cache: final rendered CGImages are cached for instant reuse.
//  - CIImage recipe chaining: orientation, crop, resize are composed without
//    allocating intermediate buffers.
//  - Fallback: when Metal device is unavailable, falls back to CPU CIContext.
//
//  Data flow: PHAsset → requestImageDataAndOrientation → Data → CIImage(data:) →
//  .oriented(orientation) → .transformed(by: scale) → CIContext.createCGImage → UIImage → cache
//

import UIKit
import Photos
import CoreImage

// MARK: - GPU Pipeline

@MainActor
private final class GPUPipeline {
    static let shared = GPUPipeline()

    let ciContext: CIContext
    private let renderQueue = DispatchQueue(label: "com.names3.ciGPU.render", qos: .userInitiated, attributes: .concurrent)

    private init() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false,
                .highQualityDownsample: true
            ])
        } else {
            ciContext = CIContext(options: [
                .useSoftwareRenderer: true,
                .cacheIntermediates: false,
                .highQualityDownsample: true
            ])
        }
    }

    func renderToUIImage(data: Data, orientation: CGImagePropertyOrientation, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { cont in
            renderQueue.async { [ciContext] in
                guard let ciImage = CIImage(data: data) else {
                    cont.resume(returning: nil)
                    return
                }

                let oriented = ciImage.oriented(orientation)
                let extent = oriented.extent

                guard extent.width > 0, extent.height > 0,
                      targetSize.width > 0, targetSize.height > 0 else {
                    cont.resume(returning: nil)
                    return
                }

                let scaleX = targetSize.width / extent.width
                let scaleY = targetSize.height / extent.height
                let scale = min(scaleX, scaleY, 1.0)

                let resized: CIImage
                if scale < 1.0 {
                    resized = oriented.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                } else {
                    resized = oriented
                }

                let outputExtent = resized.extent
                guard let cgImage = ciContext.createCGImage(resized, from: outputExtent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else {
                    cont.resume(returning: nil)
                    return
                }

                let uiImage = UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
                cont.resume(returning: uiImage)
            }
        }
    }

    func renderThumbnail(data: Data, orientation: CGImagePropertyOrientation, maxEdge: CGFloat = 400) async -> UIImage? {
        await withCheckedContinuation { cont in
            renderQueue.async { [ciContext] in
                guard let ciImage = CIImage(data: data) else {
                    cont.resume(returning: nil)
                    return
                }

                let oriented = ciImage.oriented(orientation)
                let extent = oriented.extent
                guard extent.width > 0, extent.height > 0 else {
                    cont.resume(returning: nil)
                    return
                }

                let longestEdge = max(extent.width, extent.height)
                let scale = min(maxEdge / longestEdge, 1.0)
                let resized = oriented.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

                guard let cgImage = ciContext.createCGImage(resized, from: resized.extent) else {
                    cont.resume(returning: nil)
                    return
                }

                cont.resume(returning: UIImage(cgImage: cgImage, scale: 1.0, orientation: .up))
            }
        }
    }
}

// MARK: - Data Provider

private actor GPUDataProvider {
    private let manager = PHImageManager.default()
    private var cache: [String: (Data, CGImagePropertyOrientation)] = [:]
    private let maxCacheEntries = 25

    func imageData(for asset: PHAsset) async -> (Data, CGImagePropertyOrientation)? {
        if let cached = cache[asset.localIdentifier] { return cached }

        let result: (Data, CGImagePropertyOrientation)? = await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
            opts.isSynchronous = false
            manager.requestImageDataAndOrientation(for: asset, options: opts) { data, _, orientation, info in
                StorageMonitor.reportIfCloudPhotoLowStorage(info: info)
                if let data { cont.resume(returning: (data, orientation)) }
                else { cont.resume(returning: nil) }
            }
        }

        if let result {
            if cache.count >= maxCacheEntries {
                let toRemove = Array(cache.keys.prefix(8))
                for k in toRemove { cache.removeValue(forKey: k) }
            }
            cache[asset.localIdentifier] = result
        }

        return result
    }

    func evict() { cache.removeAll() }
}

// MARK: - Texture Cache (Rendered Image Cache)

@MainActor
private final class TextureCache {
    private let rendered = NSCache<NSString, UIImage>()
    private let thumbnail = NSCache<NSString, UIImage>()

    init() {
        rendered.totalCostLimit = 70 * 1024 * 1024
        rendered.countLimit = 80
        thumbnail.totalCostLimit = 12 * 1024 * 1024
        thumbnail.countLimit = 120

        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rendered.removeAllObjects()
            self?.thumbnail.removeAllObjects()
        }
    }

    func getRendered(_ key: String) -> UIImage? { rendered.object(forKey: key as NSString) }
    func getThumbnail(_ assetID: String) -> UIImage? { thumbnail.object(forKey: assetID as NSString) }

    func setRendered(_ img: UIImage, key: String) {
        rendered.setObject(img, forKey: key as NSString, cost: imageCost(img))
    }

    func setThumbnail(_ img: UIImage, assetID: String) {
        thumbnail.setObject(img, forKey: assetID as NSString, cost: imageCost(img))
    }

    private func imageCost(_ img: UIImage) -> Int {
        guard let cg = img.cgImage else { return 0 }
        return cg.width * cg.height * 4
    }
}

// MARK: - Driver

@MainActor
final class PhotoArch4_CoreImageGPUDriver: PhotoCarouselDriver {
    static let shared = PhotoArch4_CoreImageGPUDriver()

    private let pipeline = GPUPipeline.shared
    private let dataProvider = GPUDataProvider()
    private let textureCache = TextureCache()
    private var warmupTasks: [Int: Task<Void, Never>] = [:]

    private init() {}

    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let key = CacheKeyGenerator.key(for: asset, size: targetSize)
        if let cached = textureCache.getRendered(key) { return cached }

        if let thumb = textureCache.getThumbnail(asset.localIdentifier) {
            Task { await self.renderAndCache(asset: asset, targetSize: targetSize, key: key) }
            return thumb
        }

        guard let (data, orientation) = await dataProvider.imageData(for: asset) else {
            return await fallbackLoad(asset: asset, targetSize: targetSize)
        }

        async let thumbTask = pipeline.renderThumbnail(data: data, orientation: orientation)
        async let displayTask = pipeline.renderToUIImage(data: data, orientation: orientation, targetSize: targetSize)

        if let thumb = await thumbTask {
            textureCache.setThumbnail(thumb, assetID: asset.localIdentifier)
        }

        if let display = await displayTask {
            textureCache.setRendered(display, key: key)
            return display
        }

        return textureCache.getThumbnail(asset.localIdentifier)
    }

    func preheat(assets: [PHAsset], targetSize: CGSize) {
        for asset in assets.prefix(6) {
            let key = CacheKeyGenerator.key(for: asset, size: targetSize)
            guard textureCache.getRendered(key) == nil else { continue }
            Task { await self.renderAndCache(asset: asset, targetSize: targetSize, key: key) }
        }
    }

    func prefetchIndices(currentPage: Int, totalCount: Int) -> [Int] {
        let lo = max(0, currentPage - 3)
        let hi = min(totalCount - 1, currentPage + 3)
        guard lo <= hi else { return [] }
        return (lo...hi).filter { $0 != currentPage }
    }

    func onCarouselAppeared(assets: [PHAsset], viewportSize: CGSize) {
        let displaySize = PhotoDisplayHelpers.displayTargetSize(for: viewportSize)

        for (i, asset) in assets.prefix(8).enumerated() {
            let key = CacheKeyGenerator.key(for: asset, size: displaySize)
            guard textureCache.getRendered(key) == nil else { continue }

            let task = Task {
                guard let (data, orientation) = await self.dataProvider.imageData(for: asset) else { return }
                guard !Task.isCancelled else { return }

                if self.textureCache.getThumbnail(asset.localIdentifier) == nil {
                    if let thumb = await self.pipeline.renderThumbnail(data: data, orientation: orientation) {
                        self.textureCache.setThumbnail(thumb, assetID: asset.localIdentifier)
                    }
                }

                guard !Task.isCancelled else { return }

                if let display = await self.pipeline.renderToUIImage(data: data, orientation: orientation, targetSize: displaySize) {
                    self.textureCache.setRendered(display, key: key)
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

    private func renderAndCache(asset: PHAsset, targetSize: CGSize, key: String) async {
        guard textureCache.getRendered(key) == nil else { return }
        guard let (data, orientation) = await dataProvider.imageData(for: asset) else { return }
        guard !Task.isCancelled else { return }
        if let display = await pipeline.renderToUIImage(data: data, orientation: orientation, targetSize: targetSize) {
            textureCache.setRendered(display, key: key)
        }
    }

    private func fallbackLoad(asset: PHAsset, targetSize: CGSize) async -> UIImage? {
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
