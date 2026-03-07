//
//  PhotoArch2_ActorDecodePool.swift
//  Names 3
//
//  Architecture 2: Actor-Isolated Decode Pool
//
//  Philosophy: All image operations are isolated inside Swift actors — no locks, no
//  data races, no concurrency bugs by construction. A dedicated ImageLoadActor handles
//  PHImageManager requests and caching. A DecodePoolActor bounds the number of concurrent
//  bitmap decodes to prevent memory spikes (max 4 parallel). An LRU eviction strategy
//  inside the cache actor tracks byte cost and evicts least-recently-used entries when
//  the budget is exceeded. Priority levels (visible > adjacent > prefetch) determine
//  which images get decoded first.
//

import UIKit
import Photos

// MARK: - Priority

private enum LoadPriority: Int, Comparable {
    case prefetch = 0
    case adjacent = 1
    case visible = 2

    static func < (lhs: LoadPriority, rhs: LoadPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Actor-Isolated LRU Cache

private actor LRUImageCache {
    private var entries: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []
    private var currentCost: Int = 0
    private let maxCost: Int

    struct CacheEntry {
        let image: UIImage
        let cost: Int
    }

    init(maxCostMB: Int = 70) {
        self.maxCost = maxCostMB * 1024 * 1024
    }

    func get(_ key: String) -> UIImage? {
        guard let entry = entries[key] else { return nil }
        touchKey(key)
        return entry.image
    }

    func set(_ image: UIImage, key: String) {
        let cost = imageCost(image)
        if let existing = entries[key] {
            currentCost -= existing.cost
            removeFromOrder(key)
        }
        evictIfNeeded(incoming: cost)
        entries[key] = CacheEntry(image: image, cost: cost)
        accessOrder.append(key)
        currentCost += cost
    }

    func evictAll() {
        entries.removeAll()
        accessOrder.removeAll()
        currentCost = 0
    }

    func contains(_ key: String) -> Bool {
        entries[key] != nil
    }

    private func touchKey(_ key: String) {
        removeFromOrder(key)
        accessOrder.append(key)
    }

    private func removeFromOrder(_ key: String) {
        if let idx = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: idx)
        }
    }

    private func evictIfNeeded(incoming: Int) {
        while currentCost + incoming > maxCost, let oldest = accessOrder.first {
            if let entry = entries.removeValue(forKey: oldest) {
                currentCost -= entry.cost
            }
            accessOrder.removeFirst()
        }
    }

    private func imageCost(_ img: UIImage) -> Int {
        guard let cg = img.cgImage else { return 0 }
        return cg.width * cg.height * 4
    }
}

// MARK: - Decode Pool Actor

private actor DecodePoolActor {
    private let maxConcurrent = 4
    private var running = 0
    private var waiting: [(CheckedContinuation<Void, Never>, LoadPriority)] = []

    func acquireSlot(priority: LoadPriority) async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiting.append((cont, priority))
            waiting.sort { $0.1 > $1.1 }
        }
    }

    func releaseSlot() {
        if let next = waiting.first {
            waiting.removeFirst()
            next.0.resume()
        } else {
            running = max(0, running - 1)
        }
    }
}

// MARK: - Image Load Actor

private actor ImageLoadActor {
    private let manager = PHCachingImageManager()

    func requestImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = .exact
            opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: opts) { image, info in
                StorageMonitor.reportIfCloudPhotoLowStorage(info: info)
                cont.resume(returning: image)
            }
        }
    }

    func requestThumbnail(for asset: PHAsset) async -> UIImage? {
        let size = CGSize(width: 400, height: 400)
        return await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .fastFormat
            opts.resizeMode = .fast
            opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: opts) { image, info in
                StorageMonitor.reportIfCloudPhotoLowStorage(info: info)
                cont.resume(returning: image)
            }
        }
    }

    func preheat(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty, targetSize.width > 0, targetSize.height > 0 else { return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .exact
        opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
        manager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: opts)
    }

    func stopPreheat(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty, targetSize.width > 0, targetSize.height > 0 else { return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .exact
        manager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: opts)
    }
}

// MARK: - Background Decoder

private enum BackgroundDecoder {
    static func decode(_ image: UIImage) async -> UIImage {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                if let mb = ProcessMemoryReporter.currentMegabytes(), mb > 380 {
                    cont.resume(returning: image)
                    return
                }
                guard let cgImage = image.cgImage else {
                    cont.resume(returning: image)
                    return
                }
                let size = CGSize(width: cgImage.width, height: cgImage.height)
                let format = UIGraphicsImageRendererFormat()
                format.scale = image.scale
                format.opaque = true
                let renderer = UIGraphicsImageRenderer(size: size, format: format)
                let decoded = renderer.image { _ in
                    UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
                        .draw(in: CGRect(origin: .zero, size: size))
                }
                cont.resume(returning: decoded)
            }
        }
    }
}

// MARK: - Driver

@MainActor
final class PhotoArch2_ActorDecodePoolDriver: PhotoCarouselDriver {
    static let shared = PhotoArch2_ActorDecodePoolDriver()

    private let cache = LRUImageCache(maxCostMB: 70)
    private let thumbCache = LRUImageCache(maxCostMB: 12)
    private let decodePool = DecodePoolActor()
    private let loader = ImageLoadActor()
    private var warmupTasks: [Int: Task<Void, Never>] = [:]
    private var memoryObserver: NSObjectProtocol?

    private init() {
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.cache.evictAll() }
            Task { await self.thumbCache.evictAll() }
        }
    }

    deinit {
        if let obs = memoryObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
        if let cached = await cache.get(cacheKey) { return cached }

        if let thumb = await thumbCache.get(asset.localIdentifier) {
            Task { await self.loadDecodeAndCache(asset: asset, targetSize: targetSize, priority: .adjacent) }
            return thumb
        }

        let thumbTask = Task.detached { [loader] in
            await loader.requestThumbnail(for: asset)
        }
        let fullTask = Task.detached { [loader] in
            await loader.requestImage(for: asset, targetSize: targetSize)
        }

        if let thumb = await thumbTask.value {
            let decoded = await decodeWithPool(thumb, priority: .visible)
            await thumbCache.set(decoded, key: asset.localIdentifier)

            Task {
                if let full = await fullTask.value {
                    let decodedFull = await self.decodeWithPool(full, priority: .visible)
                    await self.cache.set(decodedFull, key: cacheKey)
                }
            }
            return decoded
        }

        if let full = await fullTask.value {
            let decoded = await decodeWithPool(full, priority: .visible)
            await cache.set(decoded, key: cacheKey)
            return decoded
        }

        return nil
    }

    func preheat(assets: [PHAsset], targetSize: CGSize) {
        Task { await loader.preheat(assets, targetSize: targetSize) }
        let thumbSize = CGSize(width: 400, height: 400)
        Task { await loader.preheat(assets, targetSize: thumbSize) }

        for asset in assets.prefix(4) {
            Task { await self.loadDecodeAndCache(asset: asset, targetSize: targetSize, priority: .prefetch) }
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
        let preload = Array(assets.prefix(8))
        Task { await loader.preheat(preload, targetSize: displaySize) }

        for (i, asset) in preload.enumerated() {
            let task = Task {
                await self.loadDecodeAndCache(asset: asset, targetSize: displaySize, priority: i == 0 ? .visible : .adjacent)
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

    private func loadDecodeAndCache(asset: PHAsset, targetSize: CGSize, priority: LoadPriority) async {
        let key = CacheKeyGenerator.key(for: asset, size: targetSize)
        guard await !cache.contains(key) else { return }

        guard let raw = await loader.requestImage(for: asset, targetSize: targetSize) else { return }
        guard !Task.isCancelled else { return }
        let decoded = await decodeWithPool(raw, priority: priority)
        guard !Task.isCancelled else { return }
        await cache.set(decoded, key: key)
    }

    private func decodeWithPool(_ image: UIImage, priority: LoadPriority) async -> UIImage {
        await decodePool.acquireSlot(priority: priority)
        let result = await BackgroundDecoder.decode(image)
        await decodePool.releaseSlot()
        return result
    }
}
