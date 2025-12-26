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

        let presets = AVAssetExportSession.exportPresets(compatibleWith: avAsset)
        let preset = presets.contains(AVAssetExportPresetPassthrough) ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        guard let export = AVAssetExportSession(asset: avAsset, presetName: preset) else {
            throw NSError(domain: "Export", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cannot create export session"])
        }

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        if fm.fileExists(atPath: tmp.path) {
            try? fm.removeItem(at: tmp)
        }
        export.outputURL = tmp
        if export.supportedFileTypes.contains(.mp4) {
            export.outputFileType = .mp4
        } else if export.supportedFileTypes.contains(.mov) {
            export.outputFileType = .mov
        } else {
            export.outputFileType = export.supportedFileTypes.first
        }
        export.shouldOptimizeForNetworkUse = true
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            export.exportAsynchronously {
                switch export.status {
                case .completed:
                    cont.resume(returning: tmp)
                case .failed:
                    cont.resume(throwing: export.error ?? NSError(domain: "Export", code: -5, userInfo: [NSLocalizedDescriptionKey: "Export failed"]))
                case .cancelled:
                    cont.resume(throwing: NSError(domain: "Export", code: -6, userInfo: [NSLocalizedDescriptionKey: "Export cancelled"]))
                default:
                    cont.resume(throwing: NSError(domain: "Export", code: -7, userInfo: [NSLocalizedDescriptionKey: "Export unknown state"]))
                }
            }
        }
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "\(UUID().uuidString).mov" : cleaned
    }
}

extension PHAsset {
    static func firstFrameImage(for asset: PHAsset, maxDimension: CGFloat) async -> UIImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
            let opts = PHVideoRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { avAsset, _, _ in
                guard let avAsset else {
                    cont.resume(returning: nil)
                    return
                }
                let gen = AVAssetImageGenerator(asset: avAsset)
                gen.appliesPreferredTrackTransform = true
                gen.requestedTimeToleranceBefore = .zero
                gen.requestedTimeToleranceAfter = .zero
                gen.maximumSize = CGSize(width: maxDimension, height: maxDimension)
                let cg = try? gen.copyCGImage(at: .zero, actualTime: nil)
                cont.resume(returning: cg.map { UIImage(cgImage: $0) })
            }
        }
    }

    static func firstFrameImage(fromVideoAt url: URL, maxDimension: CGFloat) -> UIImage? {
        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        gen.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        if let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) {
            return UIImage(cgImage: cg)
        }
        return nil
    }
}