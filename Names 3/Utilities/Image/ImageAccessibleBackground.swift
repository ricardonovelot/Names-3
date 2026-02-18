import UIKit
import SwiftUI

/// Derives an accessible, image-matching color from a photo for use as the background of content below the image (e.g. contact details notes section).
/// Samples the bottom portion of the image, darkens and desaturates so white text meets contrast requirements.
enum ImageAccessibleBackground {

    /// Fraction of image height to sample from the bottom (where content meets the image).
    private static let sampleRegionHeightFraction: CGFloat = 0.35
    /// Max dimension for the bitmap we sample from (keeps work on main thread small).
    private static let sampleMaxDimension: CGFloat = 120
    /// Target luminance so background is dark but visibly tinted (Apple Maps style). Higher = more color visible.
    private static let targetMaxLuminance: CGFloat = 0.15
    /// Blend toward black (0–1). Lower = keep more of the photo’s color.
    private static let darkenAmount: CGFloat = 0.48
    /// Desaturate (0–1). Lower = more of the photo’s actual hue (green, brown, blue, etc.).
    private static let desaturateAmount: CGFloat = 0.14

    /// Returns an accessible background color derived from the bottom of the image, and a darker variant for gradient end.
    /// Run from a background queue; returns UIKit colors for use in SwiftUI.
    static func accessibleColors(from image: UIImage) -> (base: UIColor, gradientEnd: UIColor)? {
        guard let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }

        // Downscale to a small bitmap for sampling
        let scale = min(sampleMaxDimension / width, sampleMaxDimension / height, 1)
        let sampleW = max(1, Int(width * scale))
        let sampleH = max(1, Int(height * scale))
        let bottomRows = max(1, Int(CGFloat(sampleH) * sampleRegionHeightFraction))

        guard let ctx = CGContext(
            data: nil,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = ctx.data else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))
        let buf = data.bindMemory(to: UInt8.self, capacity: sampleW * sampleH * 4)

        var rSum: Double = 0, gSum: Double = 0, bSum: Double = 0
        var count = 0
        let startRow = sampleH - bottomRows
        for y in startRow..<sampleH {
            for x in 0..<sampleW {
                let offset = (y * sampleW + x) * 4
                rSum += Double(buf[offset]) / 255
                gSum += Double(buf[offset + 1]) / 255
                bSum += Double(buf[offset + 2]) / 255
                count += 1
            }
        }
        guard count > 0 else { return nil }

        var r = CGFloat(rSum / Double(count))
        var g = CGFloat(gSum / Double(count))
        var b = CGFloat(bSum / Double(count))

        // Desaturate
        let l = luminance(r: r, g: g, b: b)
        let s = desaturateAmount
        r = r * (1 - s) + l * s
        g = g * (1 - s) + l * s
        b = b * (1 - s) + l * s

        // Darken so we're in a readable range but keep hue visible (Apple Maps–style)
        var currentL = luminance(r: r, g: g, b: b)
        if currentL > targetMaxLuminance {
            let scale = targetMaxLuminance / max(currentL, 0.01)
            r *= scale
            g *= scale
            b *= scale
        }
        r = r * (1 - darkenAmount)
        g = g * (1 - darkenAmount)
        b = b * (1 - darkenAmount)

        let base = UIColor(red: r, green: g, blue: b, alpha: 1)
        let end = UIColor(red: r * 0.55, green: g * 0.55, blue: b * 0.55, alpha: 1)
        return (base, end)
    }

    private static func luminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Computes accessible colors from the image and writes them into the contact's stored gradient. Call after setting contact.photo, then save the model context.
    static func updateContactPhotoGradient(_ contact: Contact, image: UIImage) {
        guard let (base, end) = accessibleColors(from: image) else {
            contact.hasPhotoGradient = false
            return
        }
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        guard base.getRed(&sr, green: &sg, blue: &sb, alpha: &sa),
              end.getRed(&er, green: &eg, blue: &eb, alpha: &ea) else {
            contact.hasPhotoGradient = false
            return
        }
        contact.hasPhotoGradient = true
        contact.photoGradientStartR = Float(sr)
        contact.photoGradientStartG = Float(sg)
        contact.photoGradientStartB = Float(sb)
        contact.photoGradientEndR = Float(er)
        contact.photoGradientEndG = Float(eg)
        contact.photoGradientEndB = Float(eb)
    }
}
