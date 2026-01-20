import TipKit
import Foundation

/// Centralized repository for all TipKit events following Apple's recommended patterns.
/// This ensures event IDs are unique and properly shared across Tips.
@MainActor
enum TipEvents {
    // MARK: - Contact Events
    static let contactCreated = Tips.Event(id: "app.tips.contact.created")
    static let contactViewed = Tips.Event(id: "app.tips.contact.viewed")
    
    // MARK: - Note Events  
    static let noteAdded = Tips.Event(id: "app.tips.note.added")
    
    // MARK: - Tag Events
    static let tagAdded = Tips.Event(id: "app.tips.tag.added")
    
    // MARK: - Quiz Events
    static let quizCompleted = Tips.Event(id: "app.tips.quiz.completed")
    
    // MARK: - Photo Events
    static let faceAssigned = Tips.Event(id: "app.tips.photo.face.assigned")
    static let multipleFacesDetected = Tips.Event(id: "app.tips.photo.faces.multiple")
}