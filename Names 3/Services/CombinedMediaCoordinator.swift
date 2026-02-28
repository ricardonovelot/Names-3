//
//  CombinedMediaCoordinator.swift
//  Names 3
//
//  Single source of truth for focused media and asset loading across Feed↔Carousel.
//  Syncs current media (PHAsset) between views. When switching, both show the exact same asset.
//  Single bridge contract: set bridgeTargetAssetID before switching; target view consumes on appear.
//
//  Shared video playback: keeps one SingleAssetPlayer alive across Feed↔Carousel morph.
//  Both views use this player when showing the same video, avoiding reload on mode switch.
//

import Foundation
import SwiftUI
import Photos
import UIKit

/// Single source for focused asset and playback state. Feed and Carousel update only through this.
@MainActor
final class CombinedMediaCoordinator: ObservableObject {
    /// The currently focused asset's localIdentifier. Read-only; use setFocusedAsset to update.
    @Published private(set) var currentAssetID: String?

    /// Shared video player used by both Feed and Carousel during morph. Stays alive across mode switch
    /// so playback continues without reload. Feed's implementation (SingleAssetPlayer) loads faster.
    let sharedVideoPlayer = SingleAssetPlayer()

    /// Bridge handoff: asset the *other* view should show when switching. Consumed once on appear.
    /// Set in performMorphToggle; target view calls consumeBridgeTarget() in onAppear.
    private(set) var bridgeTargetAssetID: String?

    /// When set, the target view should scroll to this asset. Cleared after consumed.
    /// Kept for backward compatibility; prefer bridgeTargetAssetID for new flows.
    @Published var scrollToAssetID: String?

    /// Callback when focused asset changes. Use for prefetch coordination.
    var onFocusedAssetDidChange: ((String?, Bool) -> Void)?

    /// Single update point for focused asset. Keeps currentAssetID and CurrentPlayback in sync.
    /// Call from Feed or Carousel when the visible item changes.
    func setFocusedAsset(_ assetID: String?, isVideo: Bool) {
        let changed = currentAssetID != assetID
        currentAssetID = assetID
        CurrentPlayback.shared.currentAssetID = isVideo ? assetID : nil
        if changed {
            onFocusedAssetDidChange?(assetID, isVideo)
        }
    }

    /// Consume and return the bridge target, if any. Call once when target view appears.
    func consumeBridgeTarget() -> String? {
        let id = bridgeTargetAssetID
        bridgeTargetAssetID = nil
        scrollToAssetID = nil
        return id
    }

    /// Consume and return the pending scroll target, if any. Deprecated: use consumeBridgeTarget().
    func consumeScrollTarget() -> String? {
        let id = scrollToAssetID
        scrollToAssetID = nil
        return id
    }

    /// Set the bridge target before switching views. The target view will consume this on appear.
    func setBridgeTarget(_ assetID: String) {
        bridgeTargetAssetID = assetID
        scrollToAssetID = assetID  // Keep for views that still read scrollToAssetID
    }

    /// Request a switch to the other view, scrolling to the given asset.
    func requestScrollToAsset(_ assetID: String) {
        setBridgeTarget(assetID)
    }

    // MARK: - Unified Asset Loading

    /// Single place for Feed prefetch. Call when visible indices change.
    func prefetchForFeed(indices: IndexSet, items: [FeedItem], viewportPx: CGSize) {
        var videoAssets: [PHAsset] = []
        var photoAssets: [PHAsset] = []
        for i in indices {
            guard items.indices.contains(i) else { continue }
            switch items[i].kind {
            case .video(let a): videoAssets.append(a)
            case .photoCarousel(let list):
                if FeatureFlags.enablePhotoPosts { photoAssets.append(contentsOf: list) }
            }
        }
        if !videoAssets.isEmpty {
            VideoPrefetcher.shared.prefetch(videoAssets)
            PlayerItemPrefetcher.shared.prefetch(videoAssets)
        }
        if FeatureFlags.enablePhotoPosts, !photoAssets.isEmpty {
            let photoPx = photoTargetSizePx(for: viewportPx)
            ImagePrefetcher.shared.preheat(photoAssets, targetSize: photoPx)
        }
    }

    /// Cancel Feed prefetch for given indices.
    func cancelPrefetchForFeed(indices: IndexSet, items: [FeedItem], viewportPx: CGSize) {
        var videoAssets: [PHAsset] = []
        var photoAssets: [PHAsset] = []
        for i in indices {
            guard items.indices.contains(i) else { continue }
            switch items[i].kind {
            case .video(let a): videoAssets.append(a)
            case .photoCarousel(let list):
                if FeatureFlags.enablePhotoPosts { photoAssets.append(contentsOf: list) }
            }
        }
        if !videoAssets.isEmpty {
            VideoPrefetcher.shared.cancel(videoAssets)
            PlayerItemPrefetcher.shared.cancel(videoAssets)
        }
        if FeatureFlags.enablePhotoPosts, !photoAssets.isEmpty {
            let photoPx = photoTargetSizePx(for: viewportPx)
            ImagePrefetcher.shared.stopPreheating(photoAssets, targetSize: photoPx)
        }
    }

    private func photoTargetSizePx(for viewportPx: CGSize) -> CGSize {
        // Solution 1: Use viewport-sized preheat for feed carousel photos so PHCachingImageManager
        // cache hits the actual display request. Previously used grid size (160–512) which never matched.
        let horizontalPadding: CGFloat = 32  // MediaFeedConstants.horizontalPadding * 2
        let maxHeightFraction: CGFloat = 0.7
        let w = max(1, viewportPx.width - horizontalPadding)
        let h = max(1, viewportPx.height * maxHeightFraction)
        return CGSize(width: min(w, 2048), height: min(h, 2048))
    }
}
