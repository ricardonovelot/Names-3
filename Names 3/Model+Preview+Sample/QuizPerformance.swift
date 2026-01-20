import Foundation
import SwiftData

@Model
final class QuizPerformance {
    var uuid: UUID = UUID()
    
    var lastQuizzedDate: Date?
    var easeFactor: Float = 2.5
    var interval: Int = 0
    var repetitions: Int = 0
    var dueDate: Date = Date()
    
    var contact: Contact?
    
    init(
        uuid: UUID = UUID(),
        contact: Contact? = nil,
        lastQuizzedDate: Date? = nil,
        easeFactor: Float = 2.5,
        interval: Int = 0,
        repetitions: Int = 0,
        dueDate: Date = Date()
    ) {
        self.uuid = uuid
        self.contact = contact
        self.lastQuizzedDate = lastQuizzedDate
        self.easeFactor = easeFactor
        self.interval = interval
        self.repetitions = repetitions
        self.dueDate = dueDate
    }
    
    func recordSuccess(quality: Int = 4) {
        let now = Date()
        lastQuizzedDate = now
        repetitions += 1
        
        easeFactor = max(1.3, easeFactor + (0.1 - (5 - Float(quality)) * (0.08 + (5 - Float(quality)) * 0.02)))
        
        if repetitions == 1 {
            interval = 1
        } else if repetitions == 2 {
            interval = 6
        } else {
            interval = Int(round(Float(interval) * easeFactor))
        }
        
        dueDate = Calendar.current.date(byAdding: .day, value: interval, to: now) ?? now
    }
    
    func recordFailure() {
        let now = Date()
        lastQuizzedDate = now
        repetitions = 0
        interval = 0
        dueDate = now
        
        easeFactor = max(1.3, easeFactor - 0.2)
    }
}