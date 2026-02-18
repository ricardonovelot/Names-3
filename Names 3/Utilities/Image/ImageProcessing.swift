import UIKit

func downscaleJPEG(data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data {
    guard let image = UIImage(data: data) else { return data }
    return jpegDataForStorage(image, maxDimension: maxDimension, quality: quality) ?? data
}

// MARK: - Stored photo sizing (reduces app storage without slowing UI)

/// Max dimension and JPEG quality for contact avatars (list + detail). Keeps avatars sharp, avoids multi‑MB blobs.
private let contactPhotoMaxDimension: CGFloat = 640
private let contactPhotoQuality: CGFloat = 0.85

/// Max dimension and JPEG quality for face thumbnails (FaceEmbedding.thumbnailData). Small grid cells.
private let faceThumbnailMaxDimension: CGFloat = 320
private let faceThumbnailQuality: CGFloat = 0.8

/// Returns JPEG Data suitable for Contact.photo. Downscales to 640pt max, quality 0.85. Use everywhere we persist contact.photo.
func jpegDataForStoredContactPhoto(_ image: UIImage) -> Data {
    jpegDataForStorage(image, maxDimension: contactPhotoMaxDimension, quality: contactPhotoQuality) ?? image.jpegData(compressionQuality: contactPhotoQuality) ?? Data()
}

/// Returns JPEG Data suitable for FaceEmbedding.thumbnailData. Downscales to 320pt max, quality 0.8. Use everywhere we persist face thumbnails.
func jpegDataForStoredFaceThumbnail(_ image: UIImage) -> Data {
    jpegDataForStorage(image, maxDimension: faceThumbnailMaxDimension, quality: faceThumbnailQuality) ?? image.jpegData(compressionQuality: faceThumbnailQuality) ?? Data()
}

private func jpegDataForStorage(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
    let width = image.size.width * image.scale
    let height = image.size.height * image.scale
    let maxSide = max(width, height)
    guard maxSide > maxDimension else {
        return image.jpegData(compressionQuality: quality)
    }
    let scale = maxDimension / maxSide
    let newSize = CGSize(width: floor(width * scale), height: floor(height * scale))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
    let scaled = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }
    return scaled.jpegData(compressionQuality: quality)
}