@preconcurrency import TipKit
import Foundation

/// Centralized repository for all TipKit events.
/// Tips.Event is Sendable; use nonisolated so #Rule macros can reference from nonisolated contexts.
enum TipEvents: Sendable {
    // MARK: - Contact Events
    nonisolated static let contactCreated = Tips.Event(id: "app.tips.contact.created")
    nonisolated static let contactViewed = Tips.Event(id: "app.tips.contact.viewed")
    
    // MARK: - Note Events
    nonisolated static let noteAdded = Tips.Event(id: "app.tips.note.added")
    
    // MARK: - Tag Events
    nonisolated static let tagAdded = Tips.Event(id: "app.tips.tag.added")
    
    // MARK: - Quiz Events
    nonisolated static let quizCompleted = Tips.Event(id: "app.tips.quiz.completed")
    
    // MARK: - Photo Events
    nonisolated static let faceAssigned = Tips.Event(id: "app.tips.photo.face.assigned")
    nonisolated static let multipleFacesDetected = Tips.Event(id: "app.tips.photo.faces.multiple")
}