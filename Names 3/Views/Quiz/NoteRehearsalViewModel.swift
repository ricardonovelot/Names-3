import SwiftUI
import SwiftData

/// ViewModel for memory rehearsal sessions (not quizzes)
/// Implements contextual reinstatement for episodic/social memory
@Observable
final class NoteRehearsalViewModel {
    // MARK: - Session State
    var rehearsalItems: [RehearsalItem] = []
    var currentIndex: Int = 0
    var currentNoteIndex: Int = 0 // Which note within current contact
    var showRecallPromptBool: Bool = false
    var revealedNotes: Set<UUID> = [] // Track which notes have been revealed
    var noteDifficulties: [UUID: Int] = [:] // Track difficulty for each note
    
    // MARK: - Dependencies
    private let modelContext: ModelContext
    
    // MARK: - Computed Properties
    var currentItem: RehearsalItem? {
        guard currentIndex >= 0 && currentIndex < rehearsalItems.count else { return nil }
        return rehearsalItems[currentIndex]
    }
    
    var currentNotes: [Note] {
        guard let item = currentItem else { return [] }
        return item.notes
    }
    
    var currentNote: Note? {
        guard currentNoteIndex >= 0 && currentNoteIndex < currentNotes.count else { return nil }
        return currentNotes[currentNoteIndex]
    }
    
    var progress: Double {
        guard !rehearsalItems.isEmpty else { return 0 }
        return Double(currentIndex) / Double(rehearsalItems.count)
    }
    
    var isComplete: Bool {
        currentIndex >= rehearsalItems.count
    }
    
    var hasMoreNotes: Bool {
        guard let item = currentItem else { return false }
        return currentNoteIndex < item.notes.count - 1
    }
    
    // MARK: - Nested Types
    struct RehearsalItem: Identifiable {
        let id = UUID()
        let contact: Contact
        let notes: [Note]
        let performance: NoteRehearsalPerformance
        
        init(contact: Contact, notes: [Note], performance: NoteRehearsalPerformance) {
            self.contact = contact
            self.notes = notes
            self.performance = performance
        }
    }
    
    // MARK: - Initialization
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Setup
    func setupRehearsal(with contacts: [Contact]) {
        let now = Date()
        var items: [RehearsalItem] = []
        
        for contact in contacts {
            // Filter: only contacts with non-archived notes
            let validNotes = (contact.notes ?? [])
                .filter { !$0.isArchived && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            
            guard !validNotes.isEmpty else { continue }
            
            let performance = getOrCreatePerformance(for: contact)
            
            // Select contacts based on spacing algorithm
            // Prioritize contacts that are due or overdue
            let isDue = performance.dueDate <= now
            let daysSinceLastRehearsal = performance.lastRehearsedDate.map {
                Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0
            } ?? Int.max
            
            items.append(RehearsalItem(
                contact: contact,
                notes: validNotes,
                performance: performance
            ))
        }
        
        // Sort by priority: due date first, then by days since last rehearsal
        items.sort { item1, item2 in
            let p1 = item1.performance
            let p2 = item2.performance
            
            let due1 = p1.dueDate <= now
            let due2 = p2.dueDate <= now
            
            if due1 != due2 {
                return due1 // Due items first
            }
            
            let days1 = p1.lastRehearsedDate.map {
                Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0
            } ?? Int.max
            
            let days2 = p2.lastRehearsedDate.map {
                Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0
            } ?? Int.max
            
            return days1 > days2 // Longer since last rehearsal first
        }
        
        // Limit to 5 contacts per session (as per spec: "5 people, 1-2 notes per person")
        rehearsalItems = Array(items.prefix(5))
        currentIndex = 0
        currentNoteIndex = 0
        showRecallPromptBool = false
        revealedNotes = []
        noteDifficulties = [:]
    }
    
    private func getOrCreatePerformance(for contact: Contact) -> NoteRehearsalPerformance {
        if let existing = contact.noteRehearsalPerformance {
            return existing
        }
        
        let performance = NoteRehearsalPerformance(contact: contact)
        modelContext.insert(performance)
        contact.noteRehearsalPerformance = performance
        return performance
    }
    
    // MARK: - Session Flow
    func showRecallPrompt() {
        showRecallPromptBool = true
    }
    
    func revealCurrentNote() {
        guard let note = currentNote else { return }
        revealedNotes.insert(note.uuid)
    }
    
    func isNoteRevealed(_ note: Note) -> Bool {
        revealedNotes.contains(note.uuid)
    }
    
    func recordDifficulty(difficulty: Int) {
        guard let note = currentNote else { return }
        noteDifficulties[note.uuid] = difficulty
    }
    
    func advanceToNextNote() {
        if hasMoreNotes {
            // Move to next note for this contact
            currentNoteIndex += 1
            // Don't reset showRecallPrompt - user already saw it for this contact
            // But reset revealed state for the new note
            // (revealedNotes is per-note, so it's fine)
        } else {
            // Finished all notes for this contact, move to next contact
            finishCurrentContact()
        }
    }
    
    private func finishCurrentContact() {
        guard let item = currentItem else { return }
        
        // Calculate average difficulty for this contact's notes
        let difficulties = item.notes.compactMap { noteDifficulties[$0.uuid] }
        let averageDifficulty = difficulties.isEmpty ? 1 : difficulties.reduce(0, +) / difficulties.count
        
        // Record rehearsal
        item.performance.recordRehearsal(difficulty: averageDifficulty)
        
        // Save context
        do {
            try modelContext.save()
        } catch {
            print("Failed to save rehearsal performance: \(error)")
        }
        
        // Move to next contact
        currentIndex += 1
        currentNoteIndex = 0
        showRecallPromptBool = false // Reset for next contact
        revealedNotes = []
        // Note: noteDifficulties persists across contacts, which is fine
    }
    
    func skipCurrentContact() {
        currentIndex += 1
        currentNoteIndex = 0
        showRecallPromptBool = false
        revealedNotes = []
    }
}
