import SwiftUI
import UIKit

struct SimpleCropView: View {
    let image: UIImage
    var onComplete: (UIImage?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var performCrop = false

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                let side = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) - 40
                CropScrollViewRepresentable(image: image, cropSize: CGSize(width: side, height: side), performCrop: $performCrop) { cropped in
                    onComplete(cropped)
                }
                .frame(width: side, height: side)
                .clipped()
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 1)
                        .blendMode(.normal)
                }
                .padding()
                Spacer(minLength: 0)
            }
            .background(Color(UIColor.systemBackground))
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onComplete(nil)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        performCrop = true
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct CropScrollViewRepresentable: UIViewRepresentable {
    let image: UIImage
    let cropSize: CGSize
    @Binding var performCrop: Bool
    let onCropped: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(image: image, cropSize: cropSize, onCropped: onCropped)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let normalized = context.coordinator.normalizedImage
        let scrollView = UIScrollView()
        scrollView.bounces = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.clipsToBounds = true
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .black

        let imageView = UIImageView(image: normalized)
        imageView.frame = CGRect(origin: .zero, size: normalized.size)
        imageView.isUserInteractionEnabled = true
        imageView.contentMode = .center

        scrollView.addSubview(imageView)
        scrollView.contentSize = normalized.size
        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView

        let minZoom = max(cropSize.width / normalized.size.width, cropSize.height / normalized.size.height)
        let maxZoom = max(minZoom * 4, 1.0)
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom
        scrollView.zoomScale = minZoom

        let offsetX = max((normalized.size.width * minZoom - cropSize.width) / 2, 0)
        let offsetY = max((normalized.size.height * minZoom - cropSize.height) / 2, 0)
        scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if performCrop {
            performCrop = false
            let cropped = context.coordinator.cropCurrentVisibleRect()
            onCropped(cropped)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let originalImage: UIImage
        let normalizedImage: UIImage
        let cropSize: CGSize
        let onCropped: (UIImage?) -> Void
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        init(image: UIImage, cropSize: CGSize, onCropped: @escaping (UIImage?) -> Void) {
            self.originalImage = image
            self.normalizedImage = Self.normalizeOrientation(of: image)
            self.cropSize = cropSize
            self.onCropped = onCropped
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func cropCurrentVisibleRect() -> UIImage? {
            guard let scrollView, let img = normalizedImage.cgImage else { return nil }
            let scale = 1.0 / scrollView.zoomScale
            let originX = max(scrollView.contentOffset.x * scale, 0)
            let originY = max(scrollView.contentOffset.y * scale, 0)
            var width = cropSize.width * scale
            var height = cropSize.height * scale

            width = min(width, CGFloat(img.width) - originX)
            height = min(height, CGFloat(img.height) - originY)

            guard width > 0, height > 0 else { return nil }
            let rect = CGRect(x: originX, y: originY, width: width, height: height).integral

            guard let cropped = img.cropping(to: rect) else { return nil }
            return UIImage(cgImage: cropped, scale: originalImage.scale, orientation: .up)
        }

        static func normalizeOrientation(of image: UIImage) -> UIImage {
            if image.imageOrientation == .up { return image }
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let normalized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return normalized ?? image
        }
    }
}