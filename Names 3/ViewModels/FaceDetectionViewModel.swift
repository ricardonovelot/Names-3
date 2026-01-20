import SwiftUI
import Vision

@MainActor
final class FaceDetectionViewModel: ObservableObject {
    struct DetectedFace: Identifiable {
        let id = UUID()
        let image: UIImage
        let observation: VNFaceObservation
        var name: String? = nil
        var isLocked: Bool = false
    }
    
    @Published var faces: [DetectedFace] = []
    @Published var isDetecting = false
    var faceObservations: [VNFaceObservation] = []
    
    private var detectionCache: [String: [DetectedFace]] = [:]
    
    func detectFaces(in image: UIImage, cacheKey: String? = nil) async {
        if let cacheKey, let cached = detectionCache[cacheKey] {
            faces = cached
            faceObservations = cached.map { $0.observation }
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
                    detectionCache[cacheKey] = detectedFaces
                }
            }
        } catch {
            print("Face detection failed: \(error)")
        }
        
        isDetecting = false
    }
    
    func clearCache() {
        detectionCache.removeAll()
    }
}

