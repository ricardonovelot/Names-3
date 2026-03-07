import Foundation
import Photos
import UIKit
import AVFoundation

@MainActor
final class ImagePrefetcher {
    static let shared = ImagePrefetcher()
    private let manager = PHCachingImageManager()

    private func imageOptions() -> PHImageRequestOptions {
        let o = PHImageRequestOptions()
        o.deliveryMode = .highQualityFormat
        o.resizeMode = .exact
        o.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
        return o
    }

    func preheat(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty, targetSize.width > 0, targetSize.height > 0 else { return }
        manager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: imageOptions())
    }

    func stopPreheating(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty, targetSize.width > 0, targetSize.height > 0 else { return }
        manager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: imageOptions())
    }

    func requestImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: imageOptions()) { image, info in
                StorageMonitor.reportIfCloudPhotoLowStorage(info: info)
                cont.resume(returning: image)
            }
        }
    }

    /// Extracts the first frame (time 0) of a video for use as a seamless preview before playback.
    func requestVideoFirstFrame(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            let opts = PHVideoRequestOptions()
            opts.deliveryMode = .fastFormat
            opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                guard let avAsset else {
                    cont.resume(returning: nil)
                    return
                }
                let gen = AVAssetImageGenerator(asset: avAsset)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = targetSize
                let time = CMTime.zero
                do {
                    let cgImage = try gen.copyCGImage(at: time, actualTime: nil)
                    cont.resume(returning: UIImage(cgImage: cgImage))
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Max dimension for progressive requests. PhotoKit returns better degraded previews for moderate sizes;
    /// larger sizes (512+) often skip intermediates and show a very pixelated preview until full download.
    private static let progressiveMaxDimension: CGFloat = 1024

    private static func capToMaxDimension(_ size: CGSize, maxDim: CGFloat) -> CGSize {
        let m = max(size.width, size.height)
        guard m > maxDim, maxDim > 0 else { return size }
        let scale = maxDim / m
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func progressiveImage(for asset: PHAsset, targetSize: CGSize) -> AsyncStream<(UIImage, Bool /* isDegraded */)> {
        let cappedSize = Self.capToMaxDimension(targetSize, maxDim: Self.progressiveMaxDimension)
        return AsyncStream { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.resizeMode = .fast
            opts.isNetworkAccessAllowed = DataUsageGuardrails.shouldAllowNetworkForFeedMedia()
            let requestID = manager.requestImage(for: asset, targetSize: cappedSize, contentMode: .aspectFill, options: opts) { image, info in
                StorageMonitor.reportIfCloudPhotoLowStorage(info: info)
                guard let image else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
                continuation.yield((image, isDegraded))
                if !isDegraded {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                self.manager.cancelImageRequest(requestID)
            }
        }
    }
}