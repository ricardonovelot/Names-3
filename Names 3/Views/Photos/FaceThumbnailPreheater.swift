import UIKit
import SwiftUI

// Scroll-driven face thumbnail preheater for the Name Faces carousel.
// - Renders circular thumbnails off-main using UIGraphicsImageRenderer
// - Caches results in ImageCacheService keyed by face UUID and pixel diameter
// - Ignores outdated preheat passes via generation parameter
actor FaceThumbnailPreheater {
    static let shared = FaceThumbnailPreheater()
    
    private let cache = ImageCacheService.shared
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var currentGeneration: Int = 0
    
    // Returns cached or freshly rendered thumbnail for a face
    func thumbnail(for face: FaceDetectionViewModel.DetectedFace, diameter: CGFloat, scale: CGFloat) async -> UIImage? {
        let key = cacheKey(for: face, diameter: diameter, scale: scale)
        if let cached = cache.image(for: key) { return cached }
        // Coalesce duplicate work
        if let task = inFlight[key] { return await task.value }
        let task = Task.detached(priority: .utility) { [weak self] () -> UIImage? in
            guard let self else { return nil }
            let img = await self.renderCircleThumbnail(from: face.image, diameter: diameter, scale: scale)
            if let img { self.cache.setImage(img, for: key) }
            return img
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }
    
    // Preheat a list of indices (faces array must match indices)
    func preheat(
        faces: [FaceDetectionViewModel.DetectedFace],
        indices: [Int],
        diameter: CGFloat,
        scale: CGFloat,
        generation: Int
    ) async {
        // Drop if an older pass
        if generation < currentGeneration { return }
        currentGeneration = generation
        
        for idx in indices {
            guard idx >= 0, idx < faces.count else { continue }
            let face = faces[idx]
            let key = cacheKey(for: face, diameter: diameter, scale: scale)
            if cache.image(for: key) != nil { continue }
            if inFlight[key] != nil { continue }
            let task = Task.detached(priority: .utility) { [weak self] () -> UIImage? in
                guard let self else { return nil }
                let img = await self.renderCircleThumbnail(from: face.image, diameter: diameter, scale: scale)
                if let img { self.cache.setImage(img, for: key) }
                return img
            }
            inFlight[key] = task
            // Fire and forget; optionally await a small subset if you want back-pressure
            _ = await task.value
            inFlight[key] = nil
        }
    }
    
    // MARK: - Rendering
    
    private func cacheKey(for face: FaceDetectionViewModel.DetectedFace, diameter: CGFloat, scale: CGFloat) -> String {
        let px = Int(diameter * scale)
        return "faceThumb-\(face.id.uuidString)-\(px)"
    }
    
    private func renderCircleThumbnail(from image: UIImage, diameter: CGFloat, scale: CGFloat) async -> UIImage? {
        // Calculate pixel size
        let pixelSide = max(1, Int(diameter * scale))
        let size = CGSize(width: pixelSide, height: pixelSide)
        
        // Prepare draw rect (aspect fill)
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return nil }
        let targetAspect = 1.0 // square
        let imgAspect = imgSize.width / imgSize.height
        
        var drawRect = CGRect(origin: .zero, size: size)
        if imgAspect > targetAspect {
            // Image wider than square — fit height, crop width
            let scaledWidth = CGFloat(pixelSide) * imgAspect
            drawRect = CGRect(x: (CGFloat(pixelSide) - scaledWidth) / 2, y: 0, width: scaledWidth, height: CGFloat(pixelSide))
        } else {
            // Image taller than square — fit width, crop height
            let scaledHeight = CGFloat(pixelSide) / imgAspect
            drawRect = CGRect(x: 0, y: (CGFloat(pixelSide) - scaledHeight) / 2, width: CGFloat(pixelSide), height: scaledHeight)
        }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // we’re drawing in pixel space already
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.cgContext.addEllipse(in: rect)
            ctx.cgContext.clip()
            image.draw(in: drawRect)
        }
        return rendered
    }
}
