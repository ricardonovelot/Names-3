@preconcurrency import AVFoundation
import Foundation

extension AVAsset {
    /// Loads tracks, duration, and playability. Use before accessing these properties synchronously.
    func loadCommonProperties() async {
        _ = try? await load(.tracks, .duration, .isPlayable)
    }

    /// Loads asset and all track properties asynchronously. Call before creating AVPlayerItem or AVVideoComposition
    /// to avoid "Asset track property accessed synchronously before being loaded" warnings.
    func loadFullyForPlayback() async {
        await loadCommonProperties()
        let tracks = (try? await load(.tracks)) ?? []
        for track in tracks {
            await track.loadCommonProperties()
        }
    }
}

extension AVAssetTrack {
    /// Loads format descriptions, size, frame rate, and transform. Use before accessing these properties synchronously.
    func loadCommonProperties() async {
        _ = try? await load(.formatDescriptions, .isEnabled, .naturalSize, .nominalFrameRate, .estimatedDataRate, .preferredTransform)
    }
}