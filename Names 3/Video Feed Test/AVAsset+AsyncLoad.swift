@preconcurrency import AVFoundation
import Foundation

extension AVAsset {
    /// Loads tracks, duration, and playability. Use before accessing these properties synchronously.
    func loadCommonProperties() async {
        _ = try? await load(.tracks, .duration, .isPlayable)
    }
}

extension AVAssetTrack {
    /// Loads format descriptions, size, frame rate, and transform. Use before accessing these properties synchronously.
    func loadCommonProperties() async {
        _ = try? await load(.formatDescriptions, .isEnabled, .naturalSize, .nominalFrameRate, .estimatedDataRate, .preferredTransform)
    }
}