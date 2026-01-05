import CoreGraphics
import Vision
import UIKit

enum FaceCrop {
    static let defaultScale: CGFloat = 2.4

    static func expandedRect(for face: VNFaceObservation, imageSize: CGSize, scale: CGFloat = defaultScale) -> CGRect {
        let w = imageSize.width
        let h = imageSize.height
        let bb = face.boundingBox

        let rect = CGRect(
            x: bb.origin.x * w - (bb.width * w * (scale - 1)) / 2,
            y: (1 - bb.origin.y - bb.height) * h - (bb.height * h * (scale - 1)) / 2,
            width: bb.width * w * scale,
            height: bb.height * h * scale
        ).integral

        let full = CGRect(origin: .zero, size: imageSize)
        return rect.intersection(full)
    }
}