//
//  PhotoCarouselImageService.swift
//  Names 3
//
//  Strategy 5: Two-tier cache. ThumbnailCache (NSCache, 400px) + PHCachingImageManager.
//  Always loads thumbnail first for instant display, then upgrades to full-res.
//  Progressive loading pattern used by Photos, Instagram.
//

import Foundation
import Photos
import UIKit

@MainActor
final class PhotoCarouselImageService: PhotoCarouselDriver {
    static let shared = PhotoCarouselImageService()

    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let thumbnailSize = CGSize(width: 400, height: 400)
    private let maxThumbnailCount = 60

    private init() {
        thumbnailCache.countLimit = maxThumbnailCount
        thumbnailCache.totalCostLimit = 400 * 400 * 4 * maxThumbnailCount
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let assetID = asset.localIdentifier
        if let cached = thumbnailCache.object(forKey: assetID as NSString), targetSize.width <= thumbnailSize.width * 1.5 {
            return cached
        }
        let thumb = await loadThumbnailIfNeeded(for: asset)
        if targetSize.width <= thumbnailSize.width * 1.5 {
            return thumb
        }
        let full = await ImagePrefetcher.shared.requestImage(for: asset, targetSize: targetSize)
        return full ?? thumb
    }

    func preheat(assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty, targetSize.width > 0, targetSize.height > 0 else { return }
        ImagePrefetcher.shared.preheat(assets, targetSize: targetSize)
        Task {
            for asset in assets.prefix(10) {
                _ = await loadThumbnailIfNeeded(for: asset)
            }
        }
    }

    func prefetchIndices(currentPage: Int, totalCount: Int) -> [Int] {
        let lo = max(0, currentPage - 3)
        let hi = min(totalCount - 1, currentPage + 3)
        return (lo...hi).filter { $0 != currentPage }
    }

    func onCarouselAppeared(assets: [PHAsset], viewportSize: CGSize) {
        let targetSize = displayTargetSize(for: viewportSize)
        let preload = Array(assets.prefix(8))
        ImagePrefetcher.shared.preheat(preload, targetSize: targetSize)
        Task {
            for asset in preload {
                _ = await loadThumbnailIfNeeded(for: asset)
            }
        }
    }

    func onCarouselDisappeared() {}

    func cancelLoad(at index: Int) {}

    private func loadThumbnailIfNeeded(for asset: PHAsset) async -> UIImage? {
        let key = asset.localIdentifier as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        let image = await ImagePrefetcher.shared.requestImage(for: asset, targetSize: thumbnailSize)
        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            thumbnailCache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    private func displayTargetSize(for viewportPx: CGSize) -> CGSize {
        let horizontalPadding: CGFloat = 32
        let maxHeightFraction: CGFloat = 0.7
        let w = max(1, viewportPx.width - horizontalPadding)
        let h = max(1, viewportPx.height * maxHeightFraction)
        return CGSize(width: min(w, 2048), height: min(h, 2048))
    }
}
