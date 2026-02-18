import SwiftUI
import Vision
import SwiftData

@MainActor
final class FaceDetectionViewModel: ObservableObject {
    struct DetectedFace: Identifiable {
        let id = UUID()
        let image: UIImage
        /// Non-nil when face came from Vision detection; nil when loaded from stored FaceEmbedding.
        var observation: VNFaceObservation?
        var name: String? = nil
        var isLocked: Bool = false
    }
    
    @Published var faces: [DetectedFace] = []
    @Published var isDetecting = false
    var faceObservations: [VNFaceObservation] = []
    
    /// Capped to avoid unbounded memory growth; each entry holds UIImages (cropped faces).
    private let detectionCacheMaxCount = 12
    private var detectionCache: [String: [DetectedFace]] = [:]
    private var detectionCacheOrder: [String] = []
    
    func detectFaces(in image: UIImage, cacheKey: String? = nil) async {
        if let cacheKey, let cached = detectionCache[cacheKey] {
            faces = cached
            faceObservations = cached.compactMap { $0.observation }
            return
        }
        
        guard let cgImage = image.cgImage else { return }
        
        isDetecting = true
        faces.removeAll()
        faceObservations.removeAll()
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        
        do {
            try handler.perform([request])
            
            if let observations = request.results as? [VNFaceObservation] {
                faceObservations = observations
                
                let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
                
                var detectedFaces: [DetectedFace] = []
                for face in observations {
                    let rect = FaceCrop.expandedRect(for: face, imageSize: imageSize)
                    if !rect.isNull && !rect.isEmpty {
                        if let cropped = cgImage.cropping(to: rect) {
                            let faceImage = UIImage(cgImage: cropped)
                            detectedFaces.append(DetectedFace(image: faceImage, observation: face))
                        }
                    }
                }
                
                faces = detectedFaces
                
                if let cacheKey {
                    evictDetectionCacheIfNeeded()
                    detectionCache[cacheKey] = detectedFaces
                    detectionCacheOrder.removeAll { $0 == cacheKey }
                    detectionCacheOrder.append(cacheKey)
                }
            }
        } catch {
            print("Face detection failed: \(error)")
        }
        
        isDetecting = false
    }
    
    /// Populate faces from stored FaceEmbedding data so we skip Vision and show known contacts immediately.
    /// Call when opening Name Faces for an asset that already has embeddings.
    func setFacesFromStored(
        embeddings: [FaceEmbedding],
        contactsByUUID: [UUID: Contact]
    ) {
        faceObservations = []
        faces = embeddings.map { embed in
            let image: UIImage
            if !embed.thumbnailData.isEmpty, let ui = UIImage(data: embed.thumbnailData) {
                image = ui
            } else {
                image = UIImage()
            }
            let name = embed.contactUUID.flatMap { contactsByUUID[$0]?.displayName }
            return DetectedFace(image: image, observation: nil, name: name, isLocked: !(name?.isEmpty ?? true))
        }
        isDetecting = false
    }
    
    /// For process reporting only; safe to call from any queue.
    var reportedFacesCount: Int { faces.count }
    var reportedCacheCount: Int { detectionCache.count }

    func clearCache() {
        detectionCache.removeAll()
        detectionCacheOrder.removeAll()
    }
    
    private func evictDetectionCacheIfNeeded() {
        while detectionCache.count >= detectionCacheMaxCount, let oldest = detectionCacheOrder.first {
            detectionCacheOrder.removeFirst()
            detectionCache.removeValue(forKey: oldest)
        }
    }
}

