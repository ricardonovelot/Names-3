//
//  ExcludeScreenshotsPreference.swift
//  Names 3
//
//  User preference for excluding images marked as screenshots. When false, includes
//  screenshots (e.g. film photos saved by screenshot, downloaded images).
//  Uses dimensions as primary signal: exclude when pixel dimensions match known
//  iPhone/iPad screen resolutions. Subtype is unreliable (screenshots from
//  AirDrop, Messages, etc. may not have photoScreenshot set).
//

import Foundation
import Photos

private struct Dimensions: Hashable {
    let w: Int, h: Int
    init(_ w: Int, _ h: Int) { self.w = w; self.h = h }
}

enum ExcludeScreenshotsPreference {
    static let userDefaultsKey = "Names3.ExcludeScreenshots"

    /// When true, exclude images with device dimensions. When false, include all (film photos, screenshots).
    /// Default true for new users; existing users who explicitly disabled keep their choice.
    static var excludeScreenshots: Bool {
        get {
            if let cached = _cachedExclude { return cached }
            let val: Bool
            if UserDefaults.standard.object(forKey: userDefaultsKey) == nil {
                val = true  // default: exclude screenshots for new users
            } else {
                val = UserDefaults.standard.bool(forKey: userDefaultsKey)
            }
            _cachedExclude = val
            return val
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            _cachedExclude = newValue
        }
    }

    /// Cached preference to avoid UserDefaults reads in hot filter loops.
    private static var _cachedExclude: Bool?

    /// Known iPhone/iPad screenshot dimensions (portrait and landscape). Updated for current devices.
    /// Includes both standard and Display Zoom variants (e.g. 1179×2556 standard vs 1206×2622 zoomed for 6.1" Pro).
    private static let knownScreenshotDimensions: Set<Dimensions> = [
        // iPhone 16 Pro Max, 15 Pro Max, 14 Pro Max
        Dimensions(1320, 2868), Dimensions(2868, 1320),
        Dimensions(1290, 2796), Dimensions(2796,  1290),
        // iPhone 16 Pro, 16, 15 Pro, 15, 14 Pro — Display Zoom
        Dimensions(1206, 2622), Dimensions(2622, 1206),
        // iPhone 16 Pro, 15 Pro, 14 Pro — standard (was missing, caused screenshots to slip through)
        Dimensions(1179, 2556), Dimensions(2556, 1179),
        // iPhone 14 Plus, 13 Pro Max, 12 Pro Max, XS Max, XR
        Dimensions(1284, 2778), Dimensions(2778, 1284),
        // iPhone 14, 13, 12, X, XS
        Dimensions(1170, 2532), Dimensions(2532, 1170),
        // iPhone 8 Plus, 7 Plus, 6s Plus, 6 Plus
        Dimensions(1242, 2208), Dimensions(2208, 1242),
        // iPhone SE 2/3, 8, 7, 6s, 6
        Dimensions(750, 1334), Dimensions(1334, 750),
        // iPhone SE 1, 5s, 5c, 5
        Dimensions(640, 1136), Dimensions(1136, 640),
        // iPhone 4s, 4
        Dimensions(640, 960), Dimensions(960, 640),
        // iPad Pro 13", 12.9"
        Dimensions(2048, 2732), Dimensions(2732, 2048),
        // iPad Pro 11"
        Dimensions(1668, 2388), Dimensions(2388, 1668),
        // iPad 10th gen, Air
        Dimensions(1640, 2360), Dimensions(2360, 1640),
        // iPad mini
        Dimensions(1488, 2266), Dimensions(2266, 1488),
    ]

    /// Returns true if dimensions match a known device screen (primary signal).
    /// Fast path: mediaSubtypes.photoScreenshot when set (single bitmask check).
    /// Fallback: dimension lookup for screenshots from AirDrop, Messages, etc. that lack subtype.
    static func isLikelyRealScreenshot(_ asset: PHAsset) -> Bool {
        if asset.mediaSubtypes.contains(.photoScreenshot) { return true }
        let w = asset.pixelWidth
        let h = asset.pixelHeight
        guard w > 0, h > 0 else { return false }
        return knownScreenshotDimensions.contains(Dimensions(w, h))
    }

    /// Returns true when we should exclude this asset (preference on + likely real screenshot).
    /// Prefer this for single-asset checks; for batch filtering, read excludeScreenshots once and use isLikelyRealScreenshot in the predicate.
    static func shouldExcludeAsScreenshot(_ asset: PHAsset) -> Bool {
        guard excludeScreenshots else { return false }
        return isLikelyRealScreenshot(asset)
    }

    /// When true, show pixel dimensions overlay on feed photos (for debugging screenshot filtering).
    static let dimensionOverlayKey = "Names3.ShowDimensionOverlay"
    static var showDimensionOverlay: Bool {
        get { UserDefaults.standard.bool(forKey: dimensionOverlayKey) }
        set { UserDefaults.standard.set(newValue, forKey: dimensionOverlayKey) }
    }

    /// Device model name for known screenshot dimensions. Returns nil for unknown (e.g. camera photos).
    static func deviceName(forWidth w: Int, height h: Int) -> String? {
        deviceNameByDimensions[Dimensions(w, h)]
    }

    private static let deviceNameByDimensions: [Dimensions: String] = [
        Dimensions(1320, 2868): "iPhone 16 Pro Max",
        Dimensions(2868, 1320): "iPhone 16 Pro Max",
        Dimensions(1290, 2796): "iPhone 15 Pro Max",
        Dimensions(2796, 1290): "iPhone 15 Pro Max",
        Dimensions(1206, 2622): "iPhone 16 Pro (zoom)",
        Dimensions(2622, 1206): "iPhone 16 Pro (zoom)",
        Dimensions(1179, 2556): "iPhone 16 Pro",
        Dimensions(2556, 1179): "iPhone 16 Pro",
        Dimensions(1284, 2778): "iPhone 14 Plus",
        Dimensions(2778, 1284): "iPhone 14 Plus",
        Dimensions(1170, 2532): "iPhone 14",
        Dimensions(2532, 1170): "iPhone 14",
        Dimensions(1242, 2208): "iPhone 8 Plus",
        Dimensions(2208, 1242): "iPhone 8 Plus",
        Dimensions(750, 1334): "iPhone 8",
        Dimensions(1334, 750): "iPhone 8",
        Dimensions(640, 1136): "iPhone SE",
        Dimensions(1136, 640): "iPhone SE",
        Dimensions(640, 960): "iPhone 4s",
        Dimensions(960, 640): "iPhone 4s",
        Dimensions(2048, 2732): "iPad Pro 13\"",
        Dimensions(2732, 2048): "iPad Pro 13\"",
        Dimensions(1668, 2388): "iPad Pro 11\"",
        Dimensions(2388, 1668): "iPad Pro 11\"",
        Dimensions(1640, 2360): "iPad Air",
        Dimensions(2360, 1640): "iPad Air",
        Dimensions(1488, 2266): "iPad mini",
        Dimensions(2266, 1488): "iPad mini",
    ]
}
