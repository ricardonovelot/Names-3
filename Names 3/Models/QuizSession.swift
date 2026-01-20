import Foundation
import SwiftData

@Model
final class QuizSession {
    var uuid: UUID = UUID()
    var contactIDs: [UUID] = []
    var currentIndex: Int = 0
    var score: Int = 0
    var wrongAnswers: Int = 0
    var skippedCount: Int = 0
    var createdAt: Date = Date()
    var lastUpdated: Date = Date()
    
    init(
        uuid: UUID = UUID(),
        contactIDs: [UUID] = [],
        currentIndex: Int = 0,
        score: Int = 0,
        wrongAnswers: Int = 0,
        skippedCount: Int = 0,
        createdAt: Date = Date(),
        lastUpdated: Date = Date()
    ) {
        self.uuid = uuid
        self.contactIDs = contactIDs
        self.currentIndex = currentIndex
        self.score = score
        self.wrongAnswers = wrongAnswers
        self.skippedCount = skippedCount
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
    }
    
    func updateProgress(currentIndex: Int, score: Int, wrongAnswers: Int, skippedCount: Int) {
        self.currentIndex = currentIndex
        self.score = score
        self.wrongAnswers = wrongAnswers
        self.skippedCount = skippedCount
        self.lastUpdated = Date()
    }
}