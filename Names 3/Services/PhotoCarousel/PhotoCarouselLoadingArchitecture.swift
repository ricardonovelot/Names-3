//
//  PhotoCarouselLoadingArchitecture.swift
//  Names 3
//
//  Two-tier cache for photo carousel loading. ThumbnailCache + PHCachingImageManager.
//  Always loads thumbnail first for instant display, then upgrades to full-res.
//

import Foundation
import Photos
import UIKit

// MARK: - Driver Protocol

/// Abstraction for image loading and prefetch. Implemented by PhotoCarouselImageService.
protocol PhotoCarouselDriver: AnyObject {
    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage?
    func preheat(assets: [PHAsset], targetSize: CGSize)
    func prefetchIndices(currentPage: Int, totalCount: Int) -> [Int]
    func onCarouselAppeared(assets: [PHAsset], viewportSize: CGSize)
    func onCarouselDisappeared()
    func cancelLoad(at index: Int)
}
