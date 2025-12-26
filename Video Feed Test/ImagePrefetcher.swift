import Foundation
import Photos
import UIKit

@MainActor
final class ImagePrefetcher {
    static let shared = ImagePrefetcher()
    private let manager = PHCachingImageManager()
    private let options: PHImageRequestOptions = {
        let o = PHImageRequestOptions()
        o.deliveryMode = .highQualityFormat
        o.resizeMode = .exact
        o.isNetworkAccessAllowed = true
        return o
    }()

    func preheat(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty, targetSize.width > 0, targetSize.height > 0 else { return }
        manager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }

    func stopPreheating(_ assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty, targetSize.width > 0, targetSize.height > 0 else { return }
        manager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: options)
    }

    func requestImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
                cont.resume(returning: image)
            }
        }
    }

    func progressiveImage(for asset: PHAsset, targetSize: CGSize) -> AsyncStream<(UIImage, Bool /* isDegraded */)> {
        AsyncStream { continuation in
            let requestID = manager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, info in
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