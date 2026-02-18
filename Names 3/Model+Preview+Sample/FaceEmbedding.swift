//
//  FaceEmbedding.swift
//  Names 3
//
//  Face embedding storage for machine learning-based face recognition
//

import Foundation
import SwiftData
import Vision  // For VNFaceObservation only; faceprint bytes come from the service

/// Stores face embedding vectors (VNFaceprint) for efficient similarity search
/// Uses Apple's Vision framework to generate 128-dimensional feature descriptors
@Model
final class FaceEmbedding {
    /// Unique identifier for this face embedding
    var uuid: UUID = UUID()
    
    /// Reference to the photo asset identifier in Photos library
    var assetIdentifier: String = ""
    
    /// Reference to the contact this face belongs to (nil if unassigned)
    var contactUUID: UUID? = nil
    
    /// The 128-dimensional face embedding vector from VNFaceprint
    /// Stored as Data for SwiftData compatibility
    var embeddingData: Data = Data()
    
    /// Face bounding box in normalized coordinates [0, 1]
    /// Format: [minX, minY, width, height]
    var boundingBox: [Float] = []
    
    /// Quality score for this face (0.0 - 1.0)
    /// Based on pose, lighting, blur, occlusion
    var qualityScore: Float = 0.0
    
    /// Face pose angles in degrees
    var yaw: Float = 0.0  // Head rotation left/right
    var pitch: Float = 0.0  // Head tilt up/down
    var roll: Float = 0.0  // Head tilt left/right
    
    /// Timestamp when this embedding was created
    var createdAt: Date = Date()
    
    /// Timestamp when this embedding was last analyzed
    var lastAnalyzedAt: Date = Date()
    
    /// Photo capture date
    var photoDate: Date = Date()
    
    /// Whether this face has been manually verified by user
    var isManuallyVerified: Bool = false
    
    /// Whether this face is marked as representative for the contact
    /// Used for selecting best faces to show
    var isRepresentative: Bool = false
    
    /// Face crop thumbnail (JPEG compressed)
    var thumbnailData: Data = Data()
    
    /// Cluster ID for grouping similar faces (nil if not clustered)
    var clusterID: UUID? = nil
    
    /// Distance to cluster centroid (for quality ranking within cluster)
    var distanceToCentroid: Float = Float.greatestFiniteMagnitude
    
    init(
        uuid: UUID = UUID(),
        assetIdentifier: String = "",
        contactUUID: UUID? = nil,
        embeddingData: Data = Data(),
        boundingBox: [Float] = [],
        qualityScore: Float = 0.0,
        yaw: Float = 0.0,
        pitch: Float = 0.0,
        roll: Float = 0.0,
        createdAt: Date = Date(),
        lastAnalyzedAt: Date = Date(),
        photoDate: Date = Date(),
        isManuallyVerified: Bool = false,
        isRepresentative: Bool = false,
        thumbnailData: Data = Data(),
        clusterID: UUID? = nil,
        distanceToCentroid: Float = Float.greatestFiniteMagnitude
    ) {
        self.uuid = uuid
        self.assetIdentifier = assetIdentifier
        self.contactUUID = contactUUID
        self.embeddingData = embeddingData
        self.boundingBox = boundingBox
        self.qualityScore = qualityScore
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.createdAt = createdAt
        self.lastAnalyzedAt = lastAnalyzedAt
        self.photoDate = photoDate
        self.isManuallyVerified = isManuallyVerified
        self.isRepresentative = isRepresentative
        self.thumbnailData = thumbnailData
        self.clusterID = clusterID
        self.distanceToCentroid = distanceToCentroid
    }
    
    /// Get the face embedding vector as Float array. Returns nil if embeddingData is archived VNFeaturePrintObservation (use observationDistance for comparison).
    var embeddingVector: [Float]? {
        if (try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: embeddingData)) != nil {
            return nil
        }
        let floatCount = embeddingData.count / MemoryLayout<Float>.size
        guard floatCount > 0, embeddingData.count == floatCount * MemoryLayout<Float>.size else {
            return nil
        }
        return embeddingData.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
    
    /// Compare with another embedding using Vision's computeDistance (for archived VNFeaturePrintObservation). Returns distance (lower = more similar), or nil if either cannot be unarchived.
    func observationDistance(to other: FaceEmbedding) -> Float? {
        guard let obs1 = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: embeddingData),
              let obs2 = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: other.embeddingData) else {
            return nil
        }
        var distance: Float = .infinity
        do {
            try obs1.computeDistance(&distance, to: obs2)
            return distance
        } catch {
            return nil
        }
    }
    
    /// Returns true if the other embedding is similar (same person). Works for both archived observations (observationDistance) and raw vectors (cosineSimilarity).
    /// Use stricter thresholds to reduce false positives (e.g. observationDistance ≤ 0.55, cosineSimilarity ≥ 0.88).
    func isSimilar(to other: FaceEmbedding, observationDistanceThreshold: Float = 0.55, cosineSimilarityThreshold: Float = 0.88) -> Bool {
        if let dist = observationDistance(to: other) {
            return dist <= observationDistanceThreshold
        }
        if let sim = cosineSimilarity(with: other) {
            return sim >= cosineSimilarityThreshold
        }
        return false
    }

    /// Compare two embedding Data values (for use off MainActor). Returns true if similar (same person).
    static func areSimilar(
        embeddingData1: Data,
        embeddingData2: Data,
        observationDistanceThreshold: Float = 0.55,
        cosineSimilarityThreshold: Float = 0.88
    ) -> Bool {
        if let obs1 = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: embeddingData1),
           let obs2 = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: embeddingData2) {
            var distance: Float = .infinity
            do {
                try obs1.computeDistance(&distance, to: obs2)
                return distance <= observationDistanceThreshold
            } catch {
                return false
            }
        }
        let vec1 = Self.floatVector(from: embeddingData1)
        let vec2 = Self.floatVector(from: embeddingData2)
        guard let v1 = vec1, let v2 = vec2, v1.count == v2.count else { return false }
        var dot: Float = 0, n1: Float = 0, n2: Float = 0
        for i in 0..<v1.count {
            dot += v1[i] * v2[i]
            n1 += v1[i] * v1[i]
            n2 += v2[i] * v2[i]
        }
        let mag = sqrt(n1) * sqrt(n2)
        guard mag > 0 else { return false }
        return (dot / mag) >= cosineSimilarityThreshold
    }

    private static func floatVector(from data: Data) -> [Float]? {
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0, data.count == count * MemoryLayout<Float>.size else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
    
    /// Create embedding data from Float array
    static func createEmbeddingData(from vector: [Float]) -> Data {
        return Data(bytes: vector, count: vector.count * MemoryLayout<Float>.size)
    }
    
    /// Calculate cosine similarity with another embedding (0.0 - 1.0, higher = more similar)
    func cosineSimilarity(with other: FaceEmbedding) -> Float? {
        guard let vec1 = self.embeddingVector,
              let vec2 = other.embeddingVector,
              vec1.count == vec2.count else {
            return nil
        }
        
        var dotProduct: Float = 0
        var norm1: Float = 0
        var norm2: Float = 0
        
        for i in 0..<vec1.count {
            dotProduct += vec1[i] * vec2[i]
            norm1 += vec1[i] * vec1[i]
            norm2 += vec2[i] * vec2[i]
        }
        
        let magnitude = sqrt(norm1) * sqrt(norm2)
        guard magnitude > 0 else { return 0 }
        
        return dotProduct / magnitude
    }
    
    /// Calculate Euclidean distance with another embedding (lower = more similar)
    func euclideanDistance(to other: FaceEmbedding) -> Float? {
        guard let vec1 = self.embeddingVector,
              let vec2 = other.embeddingVector,
              vec1.count == vec2.count else {
            return nil
        }
        
        var sumSquares: Float = 0
        for i in 0..<vec1.count {
            let diff = vec1[i] - vec2[i]
            sumSquares += diff * diff
        }
        
        return sqrt(sumSquares)
    }
}

/// Extension for creating FaceEmbedding from Vision observation and pre-extracted embedding data.
/// (VNFaceprint is not in the public Vision API; the service extracts the descriptor bytes.)
extension FaceEmbedding {
    /// Create FaceEmbedding from pre-extracted embedding data and VNFaceObservation
    static func from(
        embeddingData: Data,
        observation: VNFaceObservation,
        assetIdentifier: String,
        photoDate: Date,
        contactUUID: UUID? = nil,
        thumbnailData: Data
    ) -> FaceEmbedding {
        // Extract bounding box
        let bbox = observation.boundingBox
        let boundingBox: [Float] = [
            Float(bbox.origin.x),
            Float(bbox.origin.y),
            Float(bbox.width),
            Float(bbox.height)
        ]
        
        // Calculate quality score based on confidence and face attributes
        var qualityScore = observation.confidence
        
        // Penalize for extreme poses
        if let yaw = observation.yaw?.floatValue,
           let pitch = observation.pitch?.floatValue,
           let roll = observation.roll?.floatValue {
            let poseAngle = sqrt(yaw * yaw + pitch * pitch + roll * roll)
            let posePenalty = max(0, 1.0 - (poseAngle / 45.0)) // Reduce score if pose > 45 degrees
            qualityScore *= posePenalty
        }
        
        return FaceEmbedding(
            assetIdentifier: assetIdentifier,
            contactUUID: contactUUID,
            embeddingData: embeddingData,
            boundingBox: boundingBox,
            qualityScore: qualityScore,
            yaw: observation.yaw?.floatValue ?? 0,
            pitch: observation.pitch?.floatValue ?? 0,
            roll: observation.roll?.floatValue ?? 0,
            photoDate: photoDate,
            thumbnailData: thumbnailData
        )
    }
}

/// Cluster centroid for face grouping
@Model
final class FaceCluster {
    var uuid: UUID = UUID()
    var contactUUID: UUID? = nil
    var centroidEmbedding: Data = Data()
    var faceCount: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var averageQuality: Float = 0.0
    
    init(
        uuid: UUID = UUID(),
        contactUUID: UUID? = nil,
        centroidEmbedding: Data = Data(),
        faceCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        averageQuality: Float = 0.0
    ) {
        self.uuid = uuid
        self.contactUUID = contactUUID
        self.centroidEmbedding = centroidEmbedding
        self.faceCount = faceCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.averageQuality = averageQuality
    }
    
    var centroidVector: [Float]? {
        let floatCount = centroidEmbedding.count / MemoryLayout<Float>.size
        guard floatCount > 0, centroidEmbedding.count == floatCount * MemoryLayout<Float>.size else {
            return nil
        }
        return centroidEmbedding.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
}
