import TipKit
import Foundation

@MainActor
final class TipManager {
    static let shared = TipManager()
    
    private init() {}
    
    func configure() {
        #if DEBUG
        // Reset tips in debug for testing
        try? Tips.resetDatastore()
        #endif
        
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }
    
    // MARK: - Event Donations
    
    func donateContactCreated() {
        Task {
            await QuickInputBulkAddTip.contactCreated.donate()
        }
    }
    
    func donateQuickNoteCreated() {
        Task {
            await QuickInputModeSwitchTip.quickNoteCreated.donate()
        }
    }
    
    func donatePhotoTaken() {
        Task {
            await QuickInputCameraTip.photoTaken.donate()
        }
    }
    
    func donateQuizCompleted(score: Int) {
        Task {
            await QuizStreakTip.quizCompleted.donate()
        }
    }
    
    func donateNoteAdded() {
        Task {
            await ContactNoteTip.noteAdded.donate()
        }
    }
    
    func donateTagAdded() {
        Task {
            await ContactTagTip.tagAdded.donate()
        }
    }
    
    func donateFaceAssigned() {
        Task {
            await PhotoFaceNamingTip.faceAssigned.donate()
        }
    }
    
    func donateMultipleFacesDetected() {
        Task {
            await PhotoMultipleFacesTip.multipleFacesDetected.donate()
        }
    }
}