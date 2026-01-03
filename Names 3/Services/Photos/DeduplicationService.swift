import Photos
import UIKit
import Vision

// MARK: - Deduplication Service

final class DeduplicationService {
    static let shared = DeduplicationService()
    
    private let photoService: PhotoLibraryServiceProtocol
    private let hashCache = ImageHashCache()
    private let featurePrintCache = FeaturePrintCache()
    
    private init(photoService: PhotoLibraryServiceProtocol = PhotoLibraryService.shared) {
        self.photoService = photoService
    }
    
    // MARK: - Public API
    
    func deduplicateAssets(_ assets: [PHAsset]) async -> [PHAsset] {
        guard !assets.isEmpty else { return [] }
        
        let groupedBySize = Dictionary(grouping: assets) { asset in
            SizeKey(width: asset.pixelWidth, height: asset.pixelHeight)
        }
        
        var uniqueAssets: [PHAsset] = []
        
        for (_, group) in groupedBySize {
            if group.count == 1 {
                uniqueAssets.append(group[0])
                continue
            }
            
            let clusters = await clusterByHash(group)
            
            for cluster in clusters {
                if cluster.count == 1 {
                    uniqueAssets.append(cluster[0])
                    continue
                }
                
                let confirmed = await confirmDistinctByVision(cluster)
                uniqueAssets.append(contentsOf: confirmed)
            }
        }
        
        let uniqueIDs = Set(uniqueAssets.map { $0.localIdentifier })
        let orderedResult = assets.filter { uniqueIDs.contains($0.localIdentifier) }
        
        return orderedResult
    }
    
    // MARK: - Private Methods
    
    private func clusterByHash(_ assets: [PHAsset]) async -> [[PHAsset]] {
        var clusters: [[PHAsset]] = []
        var clusterHashes: [[UInt64]] = []
        let threshold = 4
        
        for asset in assets {
            guard let hash = await computeHash(for: asset) else {
                clusters.append([asset])
                clusterHashes.append([])
                continue
            }
            
            var placed = false
            for i in 0..<clusterHashes.count {
                if clusterHashes[i].contains(where: { hammingDistance($0, hash) <= threshold }) {
                    clusterHashes[i].append(hash)
                    clusters[i].append(asset)
                    placed = true
                    break
                }
            }
            
            if !placed {
                clusters.append([asset])
                clusterHashes.append([hash])
            }
        }
        
        return clusters
    }
    
    private func confirmDistinctByVision(_ assets: [PHAsset]) async -> [PHAsset] {
        var distinct: [PHAsset] = []
        var featurePrints: [VNFeaturePrintObservation] = []
        let threshold: Float = 3.0
        
        for asset in assets {
            guard let featurePrint = await computeFeaturePrint(for: asset) else {
                distinct.append(asset)
                continue
            }
            
            var isDuplicate = false
            for existingPrint in featurePrints {
                var distance: Float = .infinity
                
                do {
                    try existingPrint.computeDistance(&distance, to: featurePrint)
                    if distance <= threshold {
                        isDuplicate = true
                        break
                    }
                } catch {
                    continue
                }
            }
            
            if !isDuplicate {
                featurePrints.append(featurePrint)
                distinct.append(asset)
            }
        }
        
        return distinct
    }
    
    private func computeHash(for asset: PHAsset) async -> UInt64? {
        if let cached = await hashCache.get(asset.localIdentifier) {
            return cached
        }
        
        guard let thumbnail = await photoService.requestImage(
            for: asset,
            targetSize: CGSize(width: 64, height: 64),
            contentMode: .aspectFill
        ) else {
            return nil
        }
        
        guard let hash = ImageHasher.computeAverageHash(for: thumbnail) else {
            return nil
        }
        
        await hashCache.set(asset.localIdentifier, hash)
        return hash
    }
    
    private func computeFeaturePrint(for asset: PHAsset) async -> VNFeaturePrintObservation? {
        if let cached = await featurePrintCache.get(asset.localIdentifier) {
            return cached
        }
        
        guard let image = await photoService.requestImage(
            for: asset,
            targetSize: CGSize(width: 512, height: 512),
            contentMode: .aspectFit
        ) else {
            return nil
        }
        
        guard let cgImage = image.cgImage else {
            return nil
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        
        do {
            try handler.perform([request])
            if let observation = request.results?.first as? VNFeaturePrintObservation {
                await featurePrintCache.set(asset.localIdentifier, observation)
                return observation
            }
        } catch {
            return nil
        }
        
        return nil
    }
    
    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}

// MARK: - Supporting Types

private struct SizeKey: Hashable {
    let width: Int
    let height: Int
}

// MARK: - Cache Actors

private actor ImageHashCache {
    private var storage: [String: UInt64] = [:]
    
    func get(_ identifier: String) -> UInt64? {
        storage[identifier]
    }
    
    func set(_ identifier: String, _ hash: UInt64) {
        storage[identifier] = hash
    }
}

private actor FeaturePrintCache {
    private var storage: [String: VNFeaturePrintObservation] = [:]
    
    func get(_ identifier: String) -> VNFeaturePrintObservation? {
        storage[identifier]
    }
    
    func set(_ identifier: String, _ featurePrint: VNFeaturePrintObservation) {
        storage[identifier] = featurePrint
    }
}

// MARK: - Image Hasher

enum ImageHasher {
    static func computeAverageHash(for image: UIImage) -> UInt64? {
        let normalized = normalizeOrientation(image)
        guard let cgImage = normalized.cgImage else { return nil }
        
        let size = 8
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: size * size * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: size,
            height: size,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        
        var luminances: [UInt8] = []
        luminances.reserveCapacity(size * size)
        var sum = 0
        
        for i in stride(from: 0, to: pixelData.count, by: 4) {
            let r = Float(pixelData[i])
            let g = Float(pixelData[i + 1])
            let b = Float(pixelData[i + 2])
            let luminance = UInt8(min(255, max(0, 0.299 * r + 0.587 * g + 0.114 * b)))
            luminances.append(luminance)
            sum += Int(luminance)
        }
        
        let average = sum / (size * size)
        
        var hash: UInt64 = 0
        for (index, luminance) in luminances.enumerated() {
            if Int(luminance) >= average {
                hash |= (1 << UInt64(index))
            }
        }
        
        return hash
    }
    
    private static func normalizeOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalized ?? image
    }
}