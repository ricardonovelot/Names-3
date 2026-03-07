//
//  PhotoArch1_ReactivePipeline.swift
//  Names 3
//
//  Architecture 1: Combine Reactive Pipeline
//
//  Philosophy: The entire image loading lifecycle is modeled as Combine publishers.
//  Every request becomes a publisher chain: cache-check → PHImageManager → decode → deliver.
//  Identical requests are deduplicated via a shared publisher map — if 3 cells request the
//  same asset, only one PHImageManager request fires and all 3 subscribers receive the result.
//  Memory pressure is observed via NotificationCenter.publisher and triggers cache eviction
//  through the same reactive graph. Progressive delivery merges a fast thumbnail publisher
//  with a slower full-quality publisher using Combine's .merge operator.
//

import UIKit
import Photos
import Combine

// MARK: - Reactive Image Cache

@MainActor
private final class ReactiveCacheStore {
    private let decodedCache = NSCache<NSString, UIImage>()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private var cancellables = Set<AnyCancellable>()

    private let maxDecodedCost = 60 * 1024 * 1024   // 60 MB decoded bitmaps
    private let maxThumbCost = 10 * 1024 * 1024      // 10 MB thumbnails
    private let thumbnailPixelSize = CGSize(width: 400, height: 400)

    init() {
        decodedCache.totalCostLimit = maxDecodedCost
        decodedCache.countLimit = 80
        thumbnailCache.totalCostLimit = maxThumbCost
        thumbnailCache.countLimit = 120

        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evictUnderPressure() }
            .store(in: &cancellables)
    }

    func decoded(for key: String) -> UIImage? { decodedCache.object(forKey: key as NSString) }
    func thumbnail(for assetID: String) -> UIImage? { thumbnailCache.object(forKey: assetID as NSString) }

    func storeDecoded(_ image: UIImage, key: String) {
        decodedCache.setObject(image, forKey: key as NSString, cost: imageCost(image))
    }

    func storeThumbnail(_ image: UIImage, assetID: String) {
        thumbnailCache.setObject(image, forKey: assetID as NSString, cost: imageCost(image))
    }

    private func evictUnderPressure() {
        decodedCache.totalCostLimit = maxDecodedCost / 2
        decodedCache.removeAllObjects()
        decodedCache.totalCostLimit = maxDecodedCost
        thumbnailCache.totalCostLimit = maxThumbCost / 2
        thumbnailCache.removeAllObjects()
        thumbnailCache.totalCostLimit = maxThumbCost
    }

    private func imageCost(_ img: UIImage) -> Int {
        guard let cg = img.cgImage else { return 0 }
        return cg.width * cg.height * 4
    }
}

// MARK: - Deduplicating Request Coordinator

@MainActor
private final class RequestDeduplicator {
    private var inflight: [String: CurrentValueSubject<UIImage?, Never>] = [:]
    private let manager = PHCachingImageManager()

    func imagePublisher(for asset: PHAsset, targetSize: CGSize) -> AnyPublisher<UIImage, Never> {
        let key = "\(asset.localIdentifier)_\(Int(targetSize.width))x\(Int(targetSize.height))"

        if let existing = inflight[key] {
            return existing.compactMap { $0 }.first().eraseToAnyPublisher()
        }

        let subject = CurrentValueSubject<UIImage?, Never>(nil)
        inflight[key] = subject

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .exact
        opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()

        manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: opts) { [weak self] image, info in
            StorageMonitor.reportIfCloudPhotoLowStorage(info: info)
            DispatchQueue.main.async {
                subject.send(image)
                subject.send(completion: .finished)
                self?.inflight.removeValue(forKey: key)
            }
        }

        return subject.compactMap { $0 }.first().eraseToAnyPublisher()
    }

    func progressivePublisher(for asset: PHAsset, targetSize: CGSize) -> AnyPublisher<(UIImage, Bool), Never> {
        let subject = PassthroughSubject<(UIImage, Bool), Never>()

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .exact
        opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()

        let reqID = manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: opts) { image, info in
            StorageMonitor.reportIfCloudPhotoLowStorage(info: info)
            guard let image else { return }
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
            DispatchQueue.main.async {
                subject.send((image, isDegraded))
                if !isDegraded { subject.send(completion: .finished) }
            }
        }

        return subject
            .handleEvents(receiveCancel: { [weak self] in
                self?.manager.cancelImageRequest(reqID)
            })
            .eraseToAnyPublisher()
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
        opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
        manager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: opts)
    }
}

// MARK: - Decode Publisher

private enum DecodePublisher {
    static func decode(_ image: UIImage) -> AnyPublisher<UIImage, Never> {
        Deferred {
            Future<UIImage, Never> { promise in
                DispatchQueue.global(qos: .userInitiated).async {
                    let decoded = forceDecodeImage(image)
                    promise(.success(decoded))
                }
            }
        }
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()
    }

    private static func forceDecodeImage(_ image: UIImage) -> UIImage {
        if let mb = ProcessMemoryReporter.currentMegabytes(), mb > 380 { return image }
        guard let cgImage = image.cgImage else { return image }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
                .draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Driver

@MainActor
final class PhotoArch1_ReactivePipelineDriver: PhotoCarouselDriver {
    static let shared = PhotoArch1_ReactivePipelineDriver()

    private let cache = ReactiveCacheStore()
    private let deduplicator = RequestDeduplicator()
    private var loadCancellables: [Int: AnyCancellable] = [:]

    private init() {}

    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
        if let cached = cache.decoded(for: cacheKey) { return cached }
        if let thumb = cache.thumbnail(for: asset.localIdentifier) {
            warmFullQuality(asset: asset, targetSize: targetSize, cacheKey: cacheKey)
            return thumb
        }

        return await withCheckedContinuation { cont in
            var received = false
            let thumbnailSize = CGSize(width: 400, height: 400)
            let thumbPub = deduplicator.imagePublisher(for: asset, targetSize: thumbnailSize)
            let fullPub = deduplicator.progressivePublisher(for: asset, targetSize: targetSize)

            var sub: AnyCancellable?
            sub = thumbPub
                .flatMap { [weak self] thumbImage -> AnyPublisher<UIImage, Never> in
                    guard let self else { return Empty().eraseToAnyPublisher() }
                    self.cache.storeThumbnail(thumbImage, assetID: asset.localIdentifier)
                    return DecodePublisher.decode(thumbImage)
                }
                .merge(with:
                    fullPub
                        .filter { !$0.1 }
                        .map(\.0)
                        .flatMap { [weak self] fullImage -> AnyPublisher<UIImage, Never> in
                            guard let self else { return Empty().eraseToAnyPublisher() }
                            return DecodePublisher.decode(fullImage)
                                .handleEvents(receiveOutput: { decoded in
                                    self.cache.storeDecoded(decoded, key: cacheKey)
                                })
                                .eraseToAnyPublisher()
                        }
                )
                .sink { image in
                    if !received {
                        received = true
                        cont.resume(returning: image)
                    }
                    sub?.cancel()
                }
        }
    }

    func preheat(assets: [PHAsset], targetSize: CGSize) {
        deduplicator.preheat(assets, targetSize: targetSize)
        let thumbnailSize = CGSize(width: 400, height: 400)
        deduplicator.preheat(assets, targetSize: thumbnailSize)
        for asset in assets.prefix(6) {
            let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
            guard cache.decoded(for: cacheKey) == nil else { continue }
            var sub: AnyCancellable?
            sub = deduplicator.imagePublisher(for: asset, targetSize: targetSize)
                .flatMap { DecodePublisher.decode($0) }
                .sink { [weak self] decoded in
                    self?.cache.storeDecoded(decoded, key: cacheKey)
                    sub?.cancel()
                }
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
        let thumbnailSize = CGSize(width: 400, height: 400)
        let preload = Array(assets.prefix(8))
        deduplicator.preheat(preload, targetSize: displaySize)
        deduplicator.preheat(preload, targetSize: thumbnailSize)

        for (i, asset) in preload.enumerated() {
            let cacheKey = CacheKeyGenerator.key(for: asset, size: displaySize)
            guard cache.decoded(for: cacheKey) == nil else { continue }
            var sub: AnyCancellable?
            sub = deduplicator.imagePublisher(for: asset, targetSize: displaySize)
                .flatMap { DecodePublisher.decode($0) }
                .sink { [weak self] decoded in
                    self?.cache.storeDecoded(decoded, key: cacheKey)
                    sub?.cancel()
                }
            loadCancellables[i] = sub
        }
    }

    func onCarouselDisappeared() {
        loadCancellables.values.forEach { $0.cancel() }
        loadCancellables.removeAll()
    }

    func cancelLoad(at index: Int) {
        loadCancellables[index]?.cancel()
        loadCancellables.removeValue(forKey: index)
    }

    private func warmFullQuality(asset: PHAsset, targetSize: CGSize, cacheKey: String) {
        guard cache.decoded(for: cacheKey) == nil else { return }
        var sub: AnyCancellable?
        sub = deduplicator.imagePublisher(for: asset, targetSize: targetSize)
            .flatMap { DecodePublisher.decode($0) }
            .sink { [weak self] decoded in
                self?.cache.storeDecoded(decoded, key: cacheKey)
                sub?.cancel()
            }
    }
}
