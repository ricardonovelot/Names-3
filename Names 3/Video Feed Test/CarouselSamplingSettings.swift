//
//  CarouselSamplingSettings.swift
//  Names 3
//
//  Controls how carousel photos are sampled when a moment has many photos.
//  Avoids showing every shot of the same outfit/scene.
//

import Foundation
import Photos

enum CarouselSamplingMode: String, CaseIterable, Identifiable {
    case none = "Show all"
    case uniform = "Uniform sampling"
    case densityAdaptive = "Density adaptive"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .none:
            return "Show every photo in each moment."
        case .uniform:
            return "Keep first, last, and evenly spaced in between. Good coverage."
        case .densityAdaptive:
            return "Fewer photos in dense bursts, more in deliberate sessions."
        }
    }
}

/// UserDefaults-backed settings for carousel sampling. Density-adaptive params are configurable.
struct CarouselSamplingSettings {
    static let modeKey = "Names3.CarouselSamplingMode"
    static let uniformMaxKey = "Names3.CarouselSamplingUniformMax"
    static let denseThresholdKey = "Names3.CarouselSamplingDenseThresholdSec"
    static let sparseThresholdKey = "Names3.CarouselSamplingSparseThresholdSec"
    static let maxDenseKey = "Names3.CarouselSamplingMaxDense"
    static let maxSparseKey = "Names3.CarouselSamplingMaxSparse"

    static var mode: CarouselSamplingMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey),
                  let m = CarouselSamplingMode(rawValue: raw) else { return .none }
            return m
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    /// Max photos per carousel when using uniform sampling.
    static var uniformMaxPerCarousel: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: uniformMaxKey)
            return v > 0 ? v : 8
        }
        set { UserDefaults.standard.set(max(3, min(20, newValue)), forKey: uniformMaxKey) }
    }

    /// Avg gap < this (seconds) = dense burst.
    static var denseThresholdSec: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: denseThresholdKey)
            return v > 0 ? v : 30
        }
        set { UserDefaults.standard.set(max(3, min(300, newValue)), forKey: denseThresholdKey) }
    }

    /// Avg gap > this (seconds) = sparse deliberate session.
    static var sparseThresholdSec: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: sparseThresholdKey)
            return v > 0 ? v : 120
        }
        set { UserDefaults.standard.set(max(30, min(3600, newValue)), forKey: sparseThresholdKey) }
    }

    /// Max photos when density is "dense" (burst).
    static var maxDense: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: maxDenseKey)
            return v > 0 ? v : 5
        }
        set { UserDefaults.standard.set(max(2, min(15, newValue)), forKey: maxDenseKey) }
    }

    /// Max photos when density is "sparse" (deliberate).
    static var maxSparse: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: maxSparseKey)
            return v > 0 ? v : 12
        }
        set { UserDefaults.standard.set(max(3, min(25, newValue)), forKey: maxSparseKey) }
    }
}

// MARK: - Sampling logic

enum CarouselSampling {
    /// Returns sampled photos. If mode is .none or count <= minShow, returns original.
    static func sample(_ photos: [PHAsset], mode: CarouselSamplingMode) -> [PHAsset] {
        if photos.isEmpty { return [] }
        let minShow = 3
        if photos.count <= minShow { return photos }
        if mode == .none { return photos }

        switch mode {
        case .none:
            return photos
        case .uniform:
            return uniformSample(photos, maxShow: CarouselSamplingSettings.uniformMaxPerCarousel)
        case .densityAdaptive:
            return densityAdaptiveSample(photos)
        }
    }

    /// First, last, and evenly spaced in between.
    static func uniformSample(_ photos: [PHAsset], maxShow: Int) -> [PHAsset] {
        let count = photos.count
        if count <= maxShow { return photos }
        if maxShow <= 1 { return Array(photos.prefix(1)) }
        if maxShow == 2 { return [photos[0], photos[count - 1]] }

        var indices: [Int] = []
        let step = Double(count - 1) / Double(maxShow - 1)
        for i in 0..<maxShow {
            let idx = i == maxShow - 1 ? count - 1 : Int(round(Double(i) * step))
            indices.append(min(idx, count - 1))
        }
        indices = Array(Set(indices)).sorted()
        return indices.map { photos[$0] }
    }

    /// Dense (avg gap < threshold) → fewer photos. Sparse (avg gap > threshold) → more.
    static func densityAdaptiveSample(_ photos: [PHAsset]) -> [PHAsset] {
        let count = photos.count
        let maxDense = CarouselSamplingSettings.maxDense
        let maxSparse = CarouselSamplingSettings.maxSparse
        if count <= maxSparse { return photos }

        let sorted = photos.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        let avgGapSec = averageGapSeconds(sorted)
        let denseThreshold = Double(CarouselSamplingSettings.denseThresholdSec)
        let sparseThreshold = Double(CarouselSamplingSettings.sparseThresholdSec)

        let maxShow: Int
        if avgGapSec < denseThreshold {
            maxShow = maxDense
        } else if avgGapSec > sparseThreshold {
            maxShow = maxSparse
        } else {
            let t = (avgGapSec - denseThreshold) / (sparseThreshold - denseThreshold)
            maxShow = Int(Double(maxDense) + t * Double(maxSparse - maxDense))
        }

        return uniformSample(sorted, maxShow: min(maxShow, count))
    }

    private static func averageGapSeconds(_ sorted: [PHAsset]) -> Double {
        guard sorted.count >= 2 else { return 0 }
        var total: TimeInterval = 0
        var count = 0
        for i in 0..<(sorted.count - 1) {
            guard let a = sorted[i].creationDate, let b = sorted[i + 1].creationDate else { continue }
            total += b.timeIntervalSince(a)
            count += 1
        }
        return count > 0 ? total / Double(count) : 0
    }
}
