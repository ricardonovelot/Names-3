import CoreGraphics
import Vision
import UIKit

enum FaceCrop {
    /// Scale for the saved contact photo (more space around face). Larger = less zoomed in.
    static let contactPhotoScale: CGFloat = 4.2
    /// Scale for face chips in Name Faces overlay; tighter so the face reads clearly in small circles.
    static let overlayScale: CGFloat = 2.5
    /// Default scale (contact photo). Kept for call sites that don't specify a context.
    static let defaultScale: CGFloat = contactPhotoScale

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