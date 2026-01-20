import TipKit
import Foundation

/// Singleton manager for TipKit configuration and event donations.
/// Uses @MainActor to ensure thread safety with TipKit's requirements.
@MainActor
final class TipManager {
    static let shared = TipManager()
    
    private var isConfigured = false
    
    private init() {}
    
    /// Configure TipKit once at app launch.
    /// Must be called on the main thread.
    func configure() {
        guard !isConfigured else { return }
        
        #if DEBUG
        try? Tips.resetDatastore()
        #endif
        
        do {
            try Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault)
            ])
            isConfigured = true
        } catch {
            print("❌ [TipManager] Failed to configure Tips: \(error)")
        }
    }
    
    // MARK: - Event Donations
    
    func donateContactCreated() {
        Task { @MainActor in
            await TipEvents.contactCreated.donate()
        }
    }
    
    func donateContactViewed() {
        Task { @MainActor in
            await TipEvents.contactViewed.donate()
        }
    }
    
    func donateQuizCompleted(score: Int) {
        Task { @MainActor in
            await TipEvents.quizCompleted.donate()
        }
    }
    
    func donateNoteAdded() {
        Task { @MainActor in
            await TipEvents.noteAdded.donate()
        }
    }
    
    func donateTagAdded() {
        Task { @MainActor in
            await TipEvents.tagAdded.donate()
        }
    }
    
    func donateFaceAssigned() {
        Task { @MainActor in
            await TipEvents.faceAssigned.donate()
        }
    }
    
    func donateMultipleFacesDetected() {
        Task { @MainActor in
            await TipEvents.multipleFacesDetected.donate()
        }
    }
    
    // MARK: - Debug Helpers
    
    #if DEBUG
    func resetAllTips() {
        Task { @MainActor in
            try? Tips.resetDatastore()
            isConfigured = false
            configure()
        }
    }
    #endif
}