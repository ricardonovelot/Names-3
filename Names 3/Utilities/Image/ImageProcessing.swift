import UIKit

func downscaleJPEG(data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data {
    guard let image = UIImage(data: data) else { return data }
    let width = image.size.width
    let height = image.size.height
    let maxSide = max(width, height)
    guard maxSide > maxDimension else {
        return image.jpegData(compressionQuality: quality) ?? data
    }
    let scale = maxDimension / maxSide
    let newSize = CGSize(width: floor(width * scale), height: floor(height * scale))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
    let scaled = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: newSize))
    }
    return scaled.jpegData(compressionQuality: quality) ?? data
}