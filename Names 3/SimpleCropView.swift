import SwiftUI
import UIKit

struct SimpleCropView: View {
    let image: UIImage
    let initialScale: CGFloat
    let initialOffset: CGSize
    var onComplete: (UIImage?, CGFloat, CGSize) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var performCrop = false

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                let side: CGFloat = 300
                CropScrollViewRepresentable(
                    image: image,
                    cropSize: CGSize(width: side, height: side),
                    initialScale: initialScale,
                    initialOffset: initialOffset,
                    performCrop: $performCrop
                ) { cropped, scale, offset in
                    onComplete(cropped, scale, offset)
                    dismiss()
                }
                .frame(width: side, height: side)
                .clipped()
                .overlay {
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(.white, lineWidth: 1)
                }
                Spacer(minLength: 0)
            }
            .background(Color.black)
            .navigationTitle("Crop Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        performCrop = true
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}

private struct CropScrollViewRepresentable: UIViewRepresentable {
    let image: UIImage
    let cropSize: CGSize
    let initialScale: CGFloat
    let initialOffset: CGSize
    @Binding var performCrop: Bool
    let onCropped: (UIImage?, CGFloat, CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            image: image,
            cropSize: cropSize,
            initialScale: initialScale,
            initialOffset: initialOffset,
            onCropped: onCropped
        )
    }

    func makeUIView(context: Context) -> UIScrollView {
        let normalized = context.coordinator.normalizedImage
        let scrollView = UIScrollView()
        scrollView.bounces = true
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.clipsToBounds = true
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .black
        scrollView.bouncesZoom = true

        let imageView = UIImageView(image: normalized)
        imageView.frame = CGRect(origin: .zero, size: normalized.size)
        imageView.isUserInteractionEnabled = true
        imageView.contentMode = .scaleAspectFit

        scrollView.addSubview(imageView)
        scrollView.contentSize = normalized.size
        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView

        let minZoom = max(cropSize.width / normalized.size.width, cropSize.height / normalized.size.height)
        let maxZoom = max(minZoom * 8, 1.0)
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = maxZoom

        // If we have valid saved crop state, restore it
        // Otherwise, fit the whole image centered
        let hasValidSavedState = initialScale > 1.0 || (initialOffset.width > 0 || initialOffset.height > 0)
        
        if hasValidSavedState {
            let restoredScale = max(min(initialScale, maxZoom), minZoom)
            scrollView.zoomScale = restoredScale
            
            DispatchQueue.main.async {
                let contentWidth = normalized.size.width * restoredScale
                let contentHeight = normalized.size.height * restoredScale
                
                let maxOffsetX = max(contentWidth - cropSize.width, 0)
                let maxOffsetY = max(contentHeight - cropSize.height, 0)
                
                let clampedX = max(min(initialOffset.width, maxOffsetX), 0)
                let clampedY = max(min(initialOffset.height, maxOffsetY), 0)
                
                scrollView.contentOffset = CGPoint(x: clampedX, y: clampedY)
            }
        } else {
            // First time cropping - fit whole image
            scrollView.zoomScale = minZoom
            
            DispatchQueue.main.async {
                let contentWidth = normalized.size.width * minZoom
                let contentHeight = normalized.size.height * minZoom
                
                let offsetX = max((contentWidth - cropSize.width) / 2, 0)
                let offsetY = max((contentHeight - cropSize.height) / 2, 0)
                scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
                
                context.coordinator.centerImageIfNeeded()
            }
        }

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if performCrop {
            DispatchQueue.main.async {
                performCrop = false
            }
            let cropped = context.coordinator.cropCurrentVisibleRect()
            let scale = uiView.zoomScale
            let offset = CGSize(width: uiView.contentOffset.x, height: uiView.contentOffset.y)
            onCropped(cropped, scale, offset)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let originalImage: UIImage
        let normalizedImage: UIImage
        let cropSize: CGSize
        let initialScale: CGFloat
        let initialOffset: CGSize
        let onCropped: (UIImage?, CGFloat, CGSize) -> Void
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        init(image: UIImage, cropSize: CGSize, initialScale: CGFloat, initialOffset: CGSize, onCropped: @escaping (UIImage?, CGFloat, CGSize) -> Void) {
            self.originalImage = image
            self.normalizedImage = Self.normalizeOrientation(of: image)
            self.cropSize = cropSize
            self.initialScale = initialScale
            self.initialOffset = initialOffset
            self.onCropped = onCropped
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImageIfNeeded()
        }

        func centerImageIfNeeded() {
            guard let scrollView = scrollView, let imageView = imageView else { return }
            
            let boundsSize = cropSize
            var frameToCenter = imageView.frame
            
            if frameToCenter.size.width < boundsSize.width {
                frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
            } else {
                frameToCenter.origin.x = 0
            }
            
            if frameToCenter.size.height < boundsSize.height {
                frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
            } else {
                frameToCenter.origin.y = 0
            }
            
            imageView.frame = frameToCenter
        }

        func cropCurrentVisibleRect() -> UIImage? {
            guard let scrollView = scrollView,
                  let imageView = imageView,
                  let img = normalizedImage.cgImage else { return nil }
            
            let scale = scrollView.zoomScale
            let imageViewFrame = imageView.frame
            
            let visibleRect = CGRect(
                x: scrollView.contentOffset.x,
                y: scrollView.contentOffset.y,
                width: cropSize.width,
                height: cropSize.height
            )
            
            let imageRect = imageViewFrame
            let intersect = visibleRect.intersection(imageRect)
            
            guard !intersect.isNull && !intersect.isEmpty else { return nil }
            
            let offsetInImageView = CGPoint(
                x: intersect.origin.x - imageRect.origin.x,
                y: intersect.origin.y - imageRect.origin.y
            )
            
            let cropRectInOriginal = CGRect(
                x: offsetInImageView.x / scale,
                y: offsetInImageView.y / scale,
                width: intersect.width / scale,
                height: intersect.height / scale
            )
            
            let finalRect = cropRectInOriginal.intersection(
                CGRect(origin: .zero, size: CGSize(width: img.width, height: img.height))
            ).integral
            
            guard !finalRect.isNull && !finalRect.isEmpty,
                  let cropped = img.cropping(to: finalRect) else { return nil }
            
            return UIImage(cgImage: cropped, scale: originalImage.scale, orientation: .up)
        }

        static func normalizeOrientation(of image: UIImage) -> UIImage {
            if image.imageOrientation == .up { return image }
            
            guard let cgImage = image.cgImage else { return image }
            let size = image.size
            
            UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
            defer { UIGraphicsEndImageContext() }
            
            image.draw(in: CGRect(origin: .zero, size: size))
            return UIGraphicsGetImageFromCurrentImageContext() ?? image
        }
    }
}