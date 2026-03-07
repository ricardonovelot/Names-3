//
//  PhotoArch5_PredictiveTripleBuffer.swift
//  Names 3
//
//  Architecture 5: Predictive Triple-Buffer
//
//  Philosophy: Eliminate all visible loading by ensuring images are always ready
//  before they're needed. Uses a triple-buffer strategy inspired by GPU rendering:
//
//   - Display buffer: the image currently shown (always ready, never blocked)
//   - Loading buffer: being filled right now by a background decode pipeline
//   - Next buffer: predicted to be needed soon, queued for loading
//
//  Scroll velocity prediction (pixels/sec) determines how many pages ahead to
//  preload: slow scroll → 1 page, medium → 2, fast swipe → 4 pages ahead.
//
//  When a carousel first enters the feed prefetch window (before it's even visible),
//  ALL its photos are aggressively fetched, decoded, and stored in a per-carousel
//  manifest. By the time the user scrolls to that carousel, every page is ready.
//
//  The manifest tracks which assets are pre-decoded and at what size. On memory
//  pressure, the manifest evicts decoded bitmaps while keeping the lightweight
//  asset references for instant re-decode.
//

import UIKit
import Photos

// MARK: - Per-Carousel Manifest

@MainActor
private final class CarouselManifest {
    let assets: [PHAsset]
    private(set) var decodedImages: [String: UIImage] = [:]
    private(set) var decodedSize: CGSize = .zero
    private var loadTasks: [String: Task<Void, Never>] = [:]

    var isFullyDecoded: Bool { decodedImages.count >= assets.count }

    init(assets: [PHAsset]) {
        self.assets = assets
    }

    func image(for assetID: String) -> UIImage? { decodedImages[assetID] }

    func store(_ image: UIImage, assetID: String, size: CGSize) {
        decodedImages[assetID] = image
        decodedSize = size
    }

    func setTask(_ task: Task<Void, Never>, assetID: String) {
        loadTasks[assetID] = task
    }

    func cancelAll() {
        loadTasks.values.forEach { $0.cancel() }
        loadTasks.removeAll()
    }

    func evictBitmaps() {
        decodedImages.removeAll()
    }

    var estimatedMemoryBytes: Int {
        decodedImages.values.reduce(0) { acc, img in
            acc + (img.cgImage.map { $0.width * $0.height * 4 } ?? 0)
        }
    }
}

// MARK: - Velocity Tracker

@MainActor
private final class VelocityTracker {
    private var samples: [(time: CFTimeInterval, offset: CGFloat)] = []
    private let maxSamples = 8

    var pixelsPerSecond: CGFloat {
        guard samples.count >= 2 else { return 0 }
        let first = samples.first!
        let last = samples.last!
        let dt = last.time - first.time
        guard dt > 0.01 else { return 0 }
        return abs(last.offset - first.offset) / CGFloat(dt)
    }

    var prefetchDepth: Int {
        let velocity = pixelsPerSecond
        switch velocity {
        case 0..<300:   return 1
        case 300..<800: return 2
        case 800..<1500: return 3
        default:         return 4
        }
    }

    func record(offset: CGFloat) {
        let now = CACurrentMediaTime()
        samples.append((now, offset))
        if samples.count > maxSamples { samples.removeFirst() }
    }

    func reset() { samples.removeAll() }
}

// MARK: - Triple Buffer Coordinator

@MainActor
private final class TripleBufferCoordinator {
    private var manifests: [String: CarouselManifest] = [:]
    private let manager = PHCachingImageManager()
    private let decodeQueue = DispatchQueue(label: "com.names3.tripleBuffer.decode", qos: .userInitiated, attributes: .concurrent)
    private var totalMemoryEstimate: Int = 0
    private let memoryBudget = 80 * 1024 * 1024
    private var memoryObserver: NSObjectProtocol?

    init() {
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.evictUnderPressure() }
    }

    deinit {
        if let obs = memoryObserver { NotificationCenter.default.removeObserver(obs) }
    }

    func manifest(for assets: [PHAsset]) -> CarouselManifest {
        let key = manifestKey(assets)
        if let existing = manifests[key] { return existing }
        let m = CarouselManifest(assets: assets)
        manifests[key] = m
        return m
    }

    func preDecodeAll(assets: [PHAsset], targetSize: CGSize) {
        let m = manifest(for: assets)
        guard !m.isFullyDecoded || m.decodedSize != targetSize else { return }

        let opts = imageOptions()
        manager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: opts)

        for asset in assets {
            let assetID = asset.localIdentifier
            guard m.image(for: assetID) == nil else { continue }

            let task = Task { @MainActor in
                let raw = await self.requestImage(asset: asset, targetSize: targetSize)
                guard !Task.isCancelled, let raw else { return }
                let decoded = await self.decodeOffMain(raw)
                guard !Task.isCancelled else { return }
                m.store(decoded, assetID: assetID, size: targetSize)
                self.updateMemoryEstimate()
            }
            m.setTask(task, assetID: assetID)
        }
    }

    func preDecodeWindow(assets: [PHAsset], center: Int, depth: Int, targetSize: CGSize) {
        let m = manifest(for: assets)
        let lo = max(0, center - depth)
        let hi = min(assets.count - 1, center + depth)
        guard lo <= hi else { return }

        for i in lo...hi {
            let asset = assets[i]
            let assetID = asset.localIdentifier
            guard m.image(for: assetID) == nil else { continue }

            let task = Task { @MainActor in
                let raw = await self.requestImage(asset: asset, targetSize: targetSize)
                guard !Task.isCancelled, let raw else { return }
                let decoded = await self.decodeOffMain(raw)
                guard !Task.isCancelled else { return }
                m.store(decoded, assetID: assetID, size: targetSize)
                self.updateMemoryEstimate()
            }
            m.setTask(task, assetID: assetID)
        }
    }

    func evictManifest(for assets: [PHAsset]) {
        let key = manifestKey(assets)
        manifests[key]?.cancelAll()
        manifests.removeValue(forKey: key)
        updateMemoryEstimate()
    }

    // MARK: - Private

    private func manifestKey(_ assets: [PHAsset]) -> String {
        guard let first = assets.first else { return "empty" }
        return "\(first.localIdentifier)_\(assets.count)"
    }

    private func requestImage(asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { cont in
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: imageOptions()) { image, info in
                StorageMonitor.reportIfCloudPhotoLowStorage(info: info)
                cont.resume(returning: image)
            }
        }
    }

    private func decodeOffMain(_ image: UIImage) async -> UIImage {
        await withCheckedContinuation { cont in
            decodeQueue.async {
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

    private func imageOptions() -> PHImageRequestOptions {
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .exact
        opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
        return opts
    }

    private func updateMemoryEstimate() {
        totalMemoryEstimate = manifests.values.reduce(0) { $0 + $1.estimatedMemoryBytes }
        if totalMemoryEstimate > memoryBudget {
            evictOldestManifests()
        }
    }

    private func evictOldestManifests() {
        let sorted = manifests.sorted { $0.value.estimatedMemoryBytes < $1.value.estimatedMemoryBytes }
        for (key, manifest) in sorted {
            if totalMemoryEstimate <= memoryBudget * 3 / 4 { break }
            totalMemoryEstimate -= manifest.estimatedMemoryBytes
            manifest.evictBitmaps()
            manifests.removeValue(forKey: key)
        }
    }

    private func evictUnderPressure() {
        for manifest in manifests.values {
            manifest.cancelAll()
            manifest.evictBitmaps()
        }
        manifests.removeAll()
        totalMemoryEstimate = 0
        manager.stopCachingImagesForAllAssets()
    }
}

// MARK: - Driver

@MainActor
final class PhotoArch5_PredictiveTripleBufferDriver: PhotoCarouselDriver {
    static let shared = PhotoArch5_PredictiveTripleBufferDriver()

    private let coordinator = TripleBufferCoordinator()
    private let velocityTracker = VelocityTracker()
    private var currentAssets: [PHAsset]?
    private var currentTargetSize: CGSize = .zero

    private init() {}

    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        if let assets = currentAssets {
            let m = coordinator.manifest(for: assets)
            if let cached = m.image(for: asset.localIdentifier) { return cached }
        }

        let raw = await requestDirect(asset: asset, targetSize: targetSize)
        guard let raw else { return nil }
        let decoded = await ImageDecodingService.decodeForDisplay(raw)
        return decoded
    }

    func preheat(assets: [PHAsset], targetSize: CGSize) {
        coordinator.preDecodeAll(assets: assets, targetSize: targetSize)
    }

    func prefetchIndices(currentPage: Int, totalCount: Int) -> [Int] {
        let depth = velocityTracker.prefetchDepth
        let lo = max(0, currentPage - depth)
        let hi = min(totalCount - 1, currentPage + depth)
        guard lo <= hi else { return [] }
        return (lo...hi).filter { $0 != currentPage }
    }

    func onCarouselAppeared(assets: [PHAsset], viewportSize: CGSize) {
        currentAssets = assets
        currentTargetSize = PhotoDisplayHelpers.displayTargetSize(for: viewportSize)
        velocityTracker.reset()
        coordinator.preDecodeAll(assets: assets, targetSize: currentTargetSize)
    }

    func onCarouselDisappeared() {
        if let assets = currentAssets {
            coordinator.evictManifest(for: assets)
        }
        currentAssets = nil
        velocityTracker.reset()
    }

    func cancelLoad(at index: Int) {
        // Manifest-based: individual cancellation not needed; manifest handles lifecycle
    }

    /// Called by the cell's scroll delegate to update velocity predictions and trigger
    /// predictive prefetch for the next buffer.
    func scrollOffsetChanged(_ offset: CGFloat) {
        velocityTracker.record(offset: offset)
        guard let assets = currentAssets, currentTargetSize.width > 0 else { return }

        let pageWidth = currentTargetSize.width / UIScreen.main.scale
        let currentPage = pageWidth > 0 ? Int(round(offset / pageWidth)) : 0
        let depth = velocityTracker.prefetchDepth

        coordinator.preDecodeWindow(assets: assets, center: currentPage, depth: depth, targetSize: currentTargetSize)
    }

    // MARK: - Private

    private func requestDirect(asset: PHAsset, targetSize: CGSize) async -> UIImage? {
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
