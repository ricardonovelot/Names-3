//
//  CombinedMediaCoordinator.swift
//  Names 3
//
//  Syncs current media (PHAsset) between Feed and Carousel views.
//  When switching views, both show the exact same asset in both directions.
//  Single bridge contract: set bridgeTargetAssetID before switching; target view consumes on appear.
//
//  Shared video playback: keeps one SingleAssetPlayer alive across Feed↔Carousel morph.
//  Both views use this player when showing the same video, avoiding reload on mode switch.
//

import Foundation
import SwiftUI
import Photos

/// Shared state for Feed + Carousel: keeps them on the same media item bidirectionally.
@MainActor
final class CombinedMediaCoordinator: ObservableObject {
    /// The currently focused asset's localIdentifier. Set by whichever view is active.
    @Published var currentAssetID: String?

    /// Shared video player used by both Feed and Carousel during morph. Stays alive across mode switch
    /// so playback continues without reload. Feed's implementation (SingleAssetPlayer) loads faster.
    let sharedVideoPlayer = SingleAssetPlayer()

    /// Bridge handoff: asset the *other* view should show when switching. Consumed once on appear.
    /// Set in performMorphToggle; target view calls consumeBridgeTarget() in onAppear.
    private(set) var bridgeTargetAssetID: String?

    /// When set, the target view should scroll to this asset. Cleared after consumed.
    /// Kept for backward compatibility; prefer bridgeTargetAssetID for new flows.
    @Published var scrollToAssetID: String?

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
}
