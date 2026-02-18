//
//  ImageDecodingService.swift
//  Names 3
//
//  Decodes UIImages off the main thread so assigning to UIImageView doesn't cause first-draw jank.
//  Apple pattern: draw into a bitmap context on a background queue so the decoded bitmap is ready.
//

import UIKit

enum ImageDecodingService {
    private static let queue = DispatchQueue(label: "com.names3.imageDecode", qos: .userInitiated)

    /// Returns a decoded copy of the image suitable for immediate display without main-thread decode.
    /// Call from a background context; the work runs on a dedicated decode queue.
    static func decodeForDisplay(_ image: UIImage?) async -> UIImage? {
        guard let image = image else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                let decoded = decodeImage(image)
                continuation.resume(returning: decoded)
            }
        }
    }

    /// Synchronous decode on the decode queue. Use from non-async code that can pass a callback.
    static func decodeForDisplay(_ image: UIImage?, completion: @escaping (UIImage?) -> Void) {
        guard let image = image else {
            completion(nil)
            return
        }
        queue.async {
            let decoded = decodeImage(image)
            DispatchQueue.main.async { completion(decoded) }
        }
    }

    /// MB threshold above which we skip decode to avoid EXC_RESOURCE (memory). Decode allocates a full bitmap (e.g. 4–16 MB per image); under pressure that can exceed the process limit.
    private static let memoryThresholdMB: Float = 380

    /// Draws the image into a new bitmap context so it's fully decoded. Runs on the receiver's queue.
    /// Skips decode when process memory is above memoryThresholdMB to avoid high-watermark crash.
    private static func decodeImage(_ image: UIImage) -> UIImage? {
        if let mb = ProcessMemoryReporter.currentMegabytes(), mb > memoryThresholdMB {
            return image
        }
        guard let cgImage = image.cgImage else { return image }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = image.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let decoded = renderer.image { context in
            UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation)
                .draw(in: CGRect(origin: .zero, size: size))
        }
        return decoded
    }
}
