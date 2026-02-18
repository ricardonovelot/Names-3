import Foundation
import SwiftData

/// Tracks rehearsal performance for notes about a contact
/// Simpler than QuizPerformance - just tracks difficulty signals and spacing
@Model
final class NoteRehearsalPerformance {
    var uuid: UUID = UUID()
    
    /// Last time notes for this contact were rehearsed
    var lastRehearsedDate: Date?
    
    /// Simple difficulty tracking: 0 = not at all, 1 = kind of, 2 = instantly
    /// Used to calculate spacing intervals
    var averageDifficulty: Float = 1.0
    
    /// Number of times rehearsed
    var rehearsalCount: Int = 0
    
    /// Next due date for rehearsal (based on spacing algorithm)
    var dueDate: Date = Date()
    
    var contact: Contact?
    
    init(
        uuid: UUID = UUID(),
        contact: Contact? = nil,
        lastRehearsedDate: Date? = nil,
        averageDifficulty: Float = 1.0,
        rehearsalCount: Int = 0,
        dueDate: Date = Date()
    ) {
        self.uuid = uuid
        self.contact = contact
        self.lastRehearsedDate = lastRehearsedDate
        self.averageDifficulty = averageDifficulty
        self.rehearsalCount = rehearsalCount
        self.dueDate = dueDate
    }
    
    /// Record a rehearsal session with difficulty signal
    /// difficulty: 0 = "Not at all", 1 = "Kind of", 2 = "Yes, instantly"
    func recordRehearsal(difficulty: Int) {
        let now = Date()
        lastRehearsedDate = now
        rehearsalCount += 1
        
        // Update running average of difficulty
        // Lower difficulty (0) = harder to remember = needs more frequent review
        // Higher difficulty (2) = easier to remember = can space out more
        let difficultyFloat = Float(difficulty)
        if rehearsalCount == 1 {
            averageDifficulty = difficultyFloat
        } else {
            // Exponential moving average (more weight to recent sessions)
            averageDifficulty = averageDifficulty * 0.7 + difficultyFloat * 0.3
        }
        
        // Calculate next due date based on difficulty
        // If remembered instantly (2), space out more
        // If not remembered (0), review soon
        let baseInterval: Int
        if averageDifficulty >= 1.8 {
            // Remembered well - space out significantly
            baseInterval = min(30, 3 + rehearsalCount * 2)
        } else if averageDifficulty >= 1.2 {
            // Remembered okay - moderate spacing
            baseInterval = min(14, 2 + rehearsalCount)
        } else {
            // Struggled - review soon
            baseInterval = 1
        }
        
        dueDate = Calendar.current.date(byAdding: .day, value: baseInterval, to: now) ?? now
    }
}
