//
//  FaceRecognitionService.swift
//  Names 3
//
//  Production-grade face recognition using Vision framework
//

import UIKit
import Vision
import Photos
import CoreImage
import Accelerate
import ImageIO

/// Service for detecting faces and generating embeddings using Apple's Vision framework
final class FaceRecognitionService {
    
    static let shared = FaceRecognitionService()
    
    private let imageManager = PHCachingImageManager()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    // Quality thresholds
    private let minimumQualityScore: Float = 0.3
    private let minimumFaceSize: CGFloat = 0.05 // 5% of image dimension
    
    // Image processing configuration
    private let targetProcessingSize = CGSize(width: 1920, height: 1920)
    
    private init() {
        imageManager.allowsCachingHighQualityImages = false
        ProcessReportCoordinator.shared.register(name: "FaceRecognitionService") { [weak self] in
            ProcessReportSnapshot(
                name: "FaceRecognitionService",
                payload: self != nil ? [
                    "state": "active",
                    "targetSize": "1920"
                ] : ["state": "released"]
            )
        }
    }
    
    // MARK: - Face Detection and Embedding
    
    /// Detects faces in a photo asset and generates embeddings
    /// - Parameters:
    ///   - asset: PHAsset to analyze
    ///   - completion: Callback with array of FaceEmbedding models
    func detectFacesAndGenerateEmbeddings(
        in asset: PHAsset,
        completion: @escaping ([FaceEmbedding]) -> Void
    ) {
        // Request image from Photos library
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .exact
        
        // Request appropriately sized image for face detection
        let targetSize = calculateOptimalSize(for: asset)
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            guard let self = self,
                  let image = image,
                  let cgImage = image.cgImage else {
                completion([])
                return
            }
            
            // Check if this is the final high-quality result
            if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded {
                return // Wait for high-quality version
            }
            
            let orientation = CGImagePropertyOrientation(image.imageOrientation)
            self.processImage(
                cgImage: cgImage,
                orientation: orientation,
                assetIdentifier: asset.localIdentifier,
                photoDate: asset.creationDate ?? Date(),
                completion: completion
            )
        }
    }
    
    /// Process a UIImage directly (for manual photos e.g. contact photo)
    func detectFacesAndGenerateEmbeddings(
        in image: UIImage,
        assetIdentifier: String,
        photoDate: Date,
        completion: @escaping ([FaceEmbedding]) -> Void
    ) {
        print("[FaceRecognition] detectFacesAndGenerateEmbeddings(in image:) assetId=\(assetIdentifier.prefix(40))...")
        guard let cgImage = image.cgImage else {
            print("[FaceRecognition] ❌ No CGImage from UIImage")
            completion([])
            return
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        print("[FaceRecognition] Image size=\(cgImage.width)x\(cgImage.height) orientation=\(orientation.rawValue)")
        processImage(
            cgImage: cgImage,
            orientation: orientation,
            assetIdentifier: assetIdentifier,
            photoDate: photoDate,
            completion: completion
        )
    }
    
    // MARK: - Private Processing Methods
    
    private func processImage(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        assetIdentifier: String,
        photoDate: Date,
        completion: @escaping ([FaceEmbedding]) -> Void
    ) {
        print("[FaceRecognition] processImage orientation=\(orientation.rawValue) size=\(cgImage.width)x\(cgImage.height)")
        // Perform face detection and landmark analysis
        let faceDetectionRequest = VNDetectFaceRectanglesRequest()
        let faceLandmarksRequest = VNDetectFaceLandmarksRequest()
        let faceCaptureQualityRequest = VNDetectFaceCaptureQualityRequest()
        
        // Use correct orientation so Vision sees faces (critical for photos from camera roll)
        let requestHandler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: orientation,
            options: [:]
        )
        
        do {
            // Perform detection
            try requestHandler.perform([
                faceDetectionRequest,
                faceLandmarksRequest,
                faceCaptureQualityRequest
            ])
            
            // Get face observations
            guard let faceResults = faceDetectionRequest.results,
                  !faceResults.isEmpty else {
                print("[FaceRecognition] ❌ No faces detected (Vision returned empty)")
                completion([])
                return
            }
            print("[FaceRecognition] Detected \(faceResults.count) face(s) confidences=\(faceResults.map { String(format: "%.2f", $0.confidence) }.joined(separator: ","))")
            
            // Filter high-quality faces
            let qualityResults = faceCaptureQualityRequest.results ?? []
            let landmarkResults = faceLandmarksRequest.results ?? []
            
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            var qualityFaces = filterQualityFaces(
                faces: faceResults,
                qualityObservations: qualityResults,
                landmarkObservations: landmarkResults,
                imageSize: imageSize
            )
            // If filter rejected all faces (e.g. strict pose/quality), use best detected face for contact photos
            if qualityFaces.isEmpty, let best = faceResults.max(by: { ($0.confidence) < ($1.confidence) }) {
                print("[FaceRecognition] Quality filter rejected all; using best face confidence=\(String(format: "%.2f", best.confidence))")
                qualityFaces = [best]
            }
            print("[FaceRecognition] Using \(qualityFaces.count) face(s) for embedding")
            
            guard !qualityFaces.isEmpty else {
                print("[FaceRecognition] ❌ No faces passed filter and no fallback")
                completion([])
                return
            }
            
            // Generate face embeddings (faceprints)
            self.generateFacePrints(
                for: qualityFaces,
                cgImage: cgImage,
                assetIdentifier: assetIdentifier,
                photoDate: photoDate,
                completion: completion
            )
            
        } catch {
            print("[FaceRecognition] ❌ Face detection error: \(error.localizedDescription)")
            completion([])
        }
    }
    
    private func filterQualityFaces(
        faces: [VNFaceObservation],
        qualityObservations: [VNFaceObservation],
        landmarkObservations: [VNFaceObservation],
        imageSize: CGSize
    ) -> [VNFaceObservation] {
        // Match quality scores to faces
        var faceQualityMap: [UUID: Float] = [:]
        for qualityObs in qualityObservations {
            if let quality = qualityObs.faceCaptureQuality {
                faceQualityMap[qualityObs.uuid] = quality
            }
        }
        
        return faces.filter { face in
            // Check minimum confidence
            guard face.confidence >= minimumQualityScore else { return false }
            
            // Check minimum face size
            let faceWidth = face.boundingBox.width * imageSize.width
            let faceHeight = face.boundingBox.height * imageSize.height
            let minDimension = min(faceWidth, faceHeight)
            let imageMinDimension = min(imageSize.width, imageSize.height)
            
            guard minDimension >= imageMinDimension * minimumFaceSize else { return false }
            
            // Check quality score if available
            if let quality = faceQualityMap[face.uuid] {
                guard quality >= minimumQualityScore else { return false }
            }
            
            // Prefer frontal faces (lower yaw/pitch)
            if let yaw = face.yaw?.floatValue,
               let pitch = face.pitch?.floatValue {
                let totalAngle = abs(yaw) + abs(pitch)
                // Allow up to 60 degrees total deviation
                guard totalAngle < 60 else { return false }
            }
            
            return true
        }
    }
    
    private func generateFacePrints(
        for faces: [VNFaceObservation],
        cgImage: CGImage,
        assetIdentifier: String,
        photoDate: Date,
        completion: @escaping ([FaceEmbedding]) -> Void
    ) {
        // Use VNGenerateImageFeaturePrintRequest on each face crop (public API; no VNGenerateFaceprintsRequest in SDK)
        var embeddings: [FaceEmbedding] = []
        print("[FaceRecognition] generateFacePrints for \(faces.count) face(s)")
        for (idx, observation) in faces.enumerated() {
            let faceCrop = extractFaceCrop(
                from: cgImage,
                boundingBox: observation.boundingBox,
                targetSize: CGSize(width: 224, height: 224)
            )
            guard let cropCGImage = faceCrop.cgImage else {
                print("[FaceRecognition] Face \(idx): no CGImage from crop")
                continue
            }
            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(cgImage: cropCGImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
                guard let result = request.results?.first as? VNFeaturePrintObservation else {
                    print("[FaceRecognition] Face \(idx): results.first is not VNFeaturePrintObservation (count=\(request.results?.count ?? 0))")
                    continue
                }
                guard let embeddingData = Self.archiveFeaturePrint(result) else {
                    print("[FaceRecognition] Face \(idx): archiveFeaturePrint returned nil")
                    continue
                }
                let thumbnailData = jpegDataForStoredFaceThumbnail(faceCrop)
                let embedding = FaceEmbedding.from(
                    embeddingData: embeddingData,
                    observation: observation,
                    assetIdentifier: assetIdentifier,
                    photoDate: photoDate,
                    thumbnailData: thumbnailData
                )
                embeddings.append(embedding)
                print("[FaceRecognition] Face \(idx): embedding created dataLen=\(embeddingData.count)")
            } catch {
                print("[FaceRecognition] Face \(idx): handler.perform error=\(error.localizedDescription)")
                continue
            }
        }
        print("[FaceRecognition] generateFacePrints done: \(embeddings.count) embedding(s)")
        completion(embeddings)
    }
    
    /// Archives VNFeaturePrintObservation for storage (raw bytes are not in public API).
    /// Compare stored embeddings via FaceEmbedding.observationDistance(to:) using computeDistance.
    private static func archiveFeaturePrint(_ observation: VNFeaturePrintObservation) -> Data? {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
            return data.isEmpty ? nil : data
        } catch {
            print("[FaceRecognition] archiveFeaturePrint failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Image Processing Utilities
    
    private func calculateOptimalSize(for asset: PHAsset) -> CGSize {
        let pixelWidth = CGFloat(asset.pixelWidth)
        let pixelHeight = CGFloat(asset.pixelHeight)
        let aspectRatio = pixelWidth / pixelHeight
        
        // Don't upscale small images
        if pixelWidth <= targetProcessingSize.width && pixelHeight <= targetProcessingSize.height {
            return CGSize(width: pixelWidth, height: pixelHeight)
        }
        
        // Scale down maintaining aspect ratio
        if aspectRatio > 1.0 {
            return CGSize(
                width: targetProcessingSize.width,
                height: targetProcessingSize.width / aspectRatio
            )
        } else {
            return CGSize(
                width: targetProcessingSize.height * aspectRatio,
                height: targetProcessingSize.height
            )
        }
    }
    
    private func extractFaceCrop(
        from cgImage: CGImage,
        boundingBox: CGRect,
        targetSize: CGSize
    ) -> UIImage {
        // Convert Vision coordinates (origin bottom-left) to UIKit (origin top-left)
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        let x = boundingBox.origin.x * imageSize.width
        let y = (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height
        let width = boundingBox.width * imageSize.width
        let height = boundingBox.height * imageSize.height
        
        // Add padding (20% on each side)
        let padding: CGFloat = 0.2
        let paddedX = max(0, x - width * padding)
        let paddedY = max(0, y - height * padding)
        let paddedWidth = min(imageSize.width - paddedX, width * (1 + 2 * padding))
        let paddedHeight = min(imageSize.height - paddedY, height * (1 + 2 * padding))
        
        let cropRect = CGRect(
            x: paddedX,
            y: paddedY,
            width: paddedWidth,
            height: paddedHeight
        )
        
        // Crop and resize
        if let croppedCGImage = cgImage.cropping(to: cropRect) {
            let croppedImage = UIImage(cgImage: croppedCGImage)
            
            // Resize to target size
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let resizedImage = renderer.image { context in
                croppedImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            
            return resizedImage
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Batch Processing
    
    /// Process multiple assets in batch with progress reporting
    func batchProcessAssets(
        _ assets: [PHAsset],
        progressHandler: @escaping (Int, Int) -> Void,
        completion: @escaping ([FaceEmbedding]) -> Void
    ) {
        var allEmbeddings: [FaceEmbedding] = []
        let lock = NSLock()
        let group = DispatchGroup()
        
        // Process in batches of 10 for memory efficiency
        let batchSize = 10
        var processedCount = 0
        
        for batchStart in stride(from: 0, to: assets.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, assets.count)
            let batch = Array(assets[batchStart..<batchEnd])
            
            for asset in batch {
                group.enter()
                
                detectFacesAndGenerateEmbeddings(in: asset) { embeddings in
                    lock.lock()
                    allEmbeddings.append(contentsOf: embeddings)
                    processedCount += 1
                    lock.unlock()
                    
                    DispatchQueue.main.async {
                        progressHandler(processedCount, assets.count)
                    }
                    
                    group.leave()
                }
            }
            
            // Wait for batch to complete before starting next
            group.wait()
        }
        
        group.notify(queue: .main) {
            completion(allEmbeddings)
        }
    }
}

// MARK: - Face Similarity Utilities

extension FaceRecognitionService {
    /// Find similar faces using cosine similarity
    /// - Parameters:
    ///   - queryEmbedding: The face embedding to search for
    ///   - candidates: Array of candidate embeddings to compare against
    ///   - threshold: Similarity threshold (0.0 - 1.0, default 0.75)
    ///   - topK: Maximum number of results to return
    /// - Returns: Array of (embedding, similarity) tuples sorted by similarity
    func findSimilarFaces(
        to queryEmbedding: FaceEmbedding,
        in candidates: [FaceEmbedding],
        threshold: Float = 0.75,
        topK: Int = 50
    ) -> [(embedding: FaceEmbedding, similarity: Float)] {
        var results: [(embedding: FaceEmbedding, similarity: Float)] = []
        
        for candidate in candidates {
            // Skip self-comparison
            guard candidate.uuid != queryEmbedding.uuid else { continue }
            
            // Calculate similarity
            if let similarity = queryEmbedding.cosineSimilarity(with: candidate),
               similarity >= threshold {
                results.append((candidate, similarity))
            }
        }
        
        // Sort by similarity (descending) and take top K
        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(topK)
            .map { $0 }
    }
    
    /// Calculate average embedding from multiple face embeddings (centroid)
    func calculateCentroid(from embeddings: [FaceEmbedding]) -> Data? {
        guard !embeddings.isEmpty else { return nil }
        
        guard let firstVector = embeddings.first?.embeddingVector else { return nil }
        let dimension = firstVector.count
        
        var centroid = [Float](repeating: 0, count: dimension)
        
        // Sum all vectors
        for embedding in embeddings {
            guard let vector = embedding.embeddingVector else { continue }
            for i in 0..<dimension {
                centroid[i] += vector[i]
            }
        }
        
        // Average
        let count = Float(embeddings.count)
        for i in 0..<dimension {
            centroid[i] /= count
        }
        
        // Normalize to unit vector
        var norm: Float = 0
        for value in centroid {
            norm += value * value
        }
        norm = sqrt(norm)
        
        if norm > 0 {
            for i in 0..<dimension {
                centroid[i] /= norm
            }
        }
        
        return FaceEmbedding.createEmbeddingData(from: centroid)
    }
}

// MARK: - Orientation for Vision

extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
