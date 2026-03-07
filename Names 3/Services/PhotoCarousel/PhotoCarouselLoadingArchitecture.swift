//
//  PhotoCarouselLoadingArchitecture.swift
//  Names 3
//
//  Abstraction layer for photo carousel image loading.
//  PhotoCarouselDriver: protocol all implementations conform to.
//  PhotoArchitectureMode: enum for A/B testing different photo loading strategies via Settings.
//

import Foundation
import Photos
import UIKit

// MARK: - Driver Protocol

/// Abstraction for image loading and prefetch. Each photo architecture implements this.
@MainActor
protocol PhotoCarouselDriver: AnyObject {
    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage?
    func preheat(assets: [PHAsset], targetSize: CGSize)
    func prefetchIndices(currentPage: Int, totalCount: Int) -> [Int]
    func onCarouselAppeared(assets: [PHAsset], viewportSize: CGSize)
    func onCarouselDisappeared()
    func cancelLoad(at index: Int)
}

// MARK: - Architecture Mode

enum PhotoArchitectureMode: String, CaseIterable, Identifiable {
    case original               = "Original (Two-Tier)"
    case reactivePipeline       = "Reactive Pipeline"
    case actorDecodePool        = "Actor Decode Pool"
    case imageIODownsampler     = "ImageIO Downsampler"
    case coreImageGPU           = "Core Image GPU"
    case predictiveTripleBuffer = "Predictive Triple-Buffer"

    var id: String { rawValue }

    static let userDefaultsKey = "photoArchitectureMode"

    var subtitle: String {
        switch self {
        case .original:
            return "Two-tier NSCache thumbnail + PHCachingImageManager full-res. Progressive thumbnail→full loading."
        case .reactivePipeline:
            return "Pure Combine publisher chain. Deduplicating requests, memory-pressure-reactive cache, progressive delivery via publisher merge."
        case .actorDecodePool:
            return "Swift actor isolation for all image ops. Bounded TaskGroup decode pool, actor-isolated LRU cache, priority-based loading."
        case .imageIODownsampler:
            return "CGImageSource thumbnails — zero full-resolution bitmaps in memory. Three-tier: EXIF→downsampled→display. Minimal memory footprint."
        case .coreImageGPU:
            return "CIContext + Metal GPU pipeline. Lazy CIImage evaluation, GPU-side resize, Metal texture cache. Zero CPU bitmap allocation."
        case .predictiveTripleBuffer:
            return "Triple-buffer swap strategy with scroll velocity prediction. Aggressive pre-decode of all carousel photos before cell appears."
        }
    }

    static var current: PhotoArchitectureMode {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? PhotoArchitectureMode.original.rawValue
        return PhotoArchitectureMode(rawValue: raw) ?? .original
    }

    @MainActor
    func makeDriver() -> PhotoCarouselDriver {
        switch self {
        case .original:               return PhotoCarouselImageService.shared
        case .reactivePipeline:       return PhotoArch1_ReactivePipelineDriver.shared
        case .actorDecodePool:        return PhotoArch2_ActorDecodePoolDriver.shared
        case .imageIODownsampler:     return PhotoArch3_ImageIODownsamplerDriver.shared
        case .coreImageGPU:           return PhotoArch4_CoreImageGPUDriver.shared
        case .predictiveTripleBuffer: return PhotoArch5_PredictiveTripleBufferDriver.shared
        }
    }
}

// MARK: - Shared Helpers

enum PhotoDisplayHelpers {
    static func displayTargetSize(for viewportPx: CGSize) -> CGSize {
        let horizontalPadding: CGFloat = 32
        let maxHeightFraction: CGFloat = 0.7
        let w = max(1, viewportPx.width - horizontalPadding)
        let h = max(1, viewportPx.height * maxHeightFraction)
        return CGSize(width: min(w, 2048), height: min(h, 2048))
    }

    @MainActor static func adjustedTargetSize(for asset: PHAsset, viewportPts: CGSize, scale: CGFloat) -> CGSize {
        let horizontalPadding: CGFloat = 16
        let maxHeightFraction: CGFloat = 0.7
        let w = viewportPts.width > 0 ? viewportPts.width : UIScreen.main.bounds.width
        let h = viewportPts.height > 0 ? viewportPts.height : UIScreen.main.bounds.height
        var sz = CGSize(
            width: min(max(1, w) - horizontalPadding * 2, CGFloat(asset.pixelWidth)) * scale,
            height: min(max(1, h) * maxHeightFraction, CGFloat(asset.pixelHeight)) * scale
        )
        if StorageMonitor.shared.isLowOnDeviceStorage {
            sz = CGSize(width: sz.width * 0.6, height: sz.height * 0.6)
        }
        return sz
    }
}
