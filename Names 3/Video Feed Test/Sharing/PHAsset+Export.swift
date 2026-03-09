import Photos
import AVFoundation
import UIKit

extension PHAsset {
    static func exportVideoToTempURL(_ asset: PHAsset) async throws -> URL {
        if asset.mediaType != .video {
            throw NSError(domain: "Export", code: -1, userInfo: [NSLocalizedDescriptionKey: "Asset is not a video"])
        }

        let avAsset: AVAsset? = await withCheckedContinuation { (cont: CheckedContinuation<AVAsset?, Never>) in
            let opts = PHVideoRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { a, _, _ in
                cont.resume(returning: a)
            }
        }
        guard let avAsset else {
            throw NSError(domain: "Export", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to load AVAsset"])
        }

        let preset: String = await withCheckedContinuation { cont in
            AVAssetExportSession.determineCompatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: avAsset, outputFileType: .mp4) { compatible in
                cont.resume(returning: compatible ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality)
            }
        }
        guard let export = AVAssetExportSession(asset: avAsset, presetName: preset) else {
            throw NSError(domain: "Export", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cannot create export session"])
        }

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        if fm.fileExists(atPath: tmp.path) {
            try? fm.removeItem(at: tmp)
        }
        let fileType: AVFileType = export.supportedFileTypes.contains(.mp4) ? .mp4 : (export.supportedFileTypes.contains(.mov) ? .mov : (export.supportedFileTypes.first ?? .mp4))
        export.shouldOptimizeForNetworkUse = true
        try await export.export(to: tmp, as: fileType)
        return tmp
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "\(UUID().uuidString).mov" : cleaned
    }
}

extension PHAsset {
    static func firstFrameImage(for asset: PHAsset, maxDimension: CGFloat) async -> UIImage? {
        let avAsset: AVAsset? = await withCheckedContinuation { cont in
            let opts = PHVideoRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { a, _, _ in
                cont.resume(returning: a)
            }
        }
        guard let avAsset else { return nil }
        let gen = AVAssetImageGenerator(asset: avAsset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        guard let (cgImage, _) = try? await gen.image(at: .zero) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    static func firstFrameImage(fromVideoAt url: URL, maxDimension: CGFloat) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        guard let (cgImage, _) = try? await gen.image(at: .zero) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}