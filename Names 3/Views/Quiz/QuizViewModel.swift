import SwiftUI
import SwiftData

@Observable
final class QuizViewModel {
    // MARK: - Published State
    var quizItems: [QuizItem] = []
    var currentIndex: Int = 0
    var userInput: String = ""
    var showFeedback: Bool = false
    var isCorrect: Bool = false
    var hintLevel: Int = 0
    var score: Int = 0
    var wrongAnswers: Int = 0
    var skippedCount: Int = 0
    var showCompletionSheet: Bool = false
    var isTextFieldFocused: Bool = false
    
    // MARK: - Dependencies
    private let modelContext: ModelContext
    private let hapticManager = HapticManager.shared
    
    // MARK: - Computed Properties
    var currentItem: QuizItem? {
        guard currentIndex >= 0 && currentIndex < quizItems.count else { return nil }
        return quizItems[currentIndex]
    }
    
    var correctName: String {
        currentItem?.contact.name ?? ""
    }
    
    var progress: Double {
        guard !quizItems.isEmpty else { return 0 }
        return Double(currentIndex) / Double(quizItems.count)
    }
    
    var hintText: String {
        guard hintLevel > 0, !correctName.isEmpty else { return "" }
        
        switch hintLevel {
        case 1:
            return String(correctName.prefix(1)) + String(repeating: "_", count: max(0, correctName.count - 1))
        case 2:
            let halfLength = correctName.count / 2
            return String(correctName.prefix(halfLength)) + String(repeating: "_", count: max(0, correctName.count - halfLength))
        default:
            return correctName
        }
    }
    
    // MARK: - Nested Types
    struct QuizItem: Identifiable {
        let id = UUID()
        let contact: Contact
        let performance: QuizPerformance
    }
    
    // MARK: - Initialization
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Setup
    func setupQuiz(with contacts: [Contact]) {
        let valid = contacts.filter { contact in
            guard let name = contact.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return false
            }
            
            let hasPhoto = !contact.photo.isEmpty && UIImage(data: contact.photo) != nil
            let hasSummary = !(contact.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasNotes = !(contact.notes?.isEmpty ?? true)
            
            return hasPhoto || hasSummary || hasNotes
        }
        
        var items: [QuizItem] = []
        for contact in valid {
            let performance = getOrCreatePerformance(for: contact)
            items.append(QuizItem(contact: contact, performance: performance))
        }
        
        items.sort { $0.performance.dueDate < $1.performance.dueDate }
        
        let sessionSize = min(10, items.count)
        quizItems = Array(items.prefix(sessionSize))
    }
    
    // MARK: - Quiz Actions
    func submitAnswer() {
        guard let item = currentItem else { return }
        
        isTextFieldFocused = false
        
        let correct = isAnswerCorrect(userAnswer: userInput, correctName: correctName)
        isCorrect = correct
        
        // Haptic feedback
        if correct {
            hapticManager.success()
        } else {
            hapticManager.error()
        }
        
        showFeedback = true
        
        if correct && hintLevel < 3 {
            score += 1
            let quality = calculateQuality()
            item.performance.recordSuccess(quality: quality)
            
            // Auto-advance with context-aware timing
            let delay = calculateAutoAdvanceDelay()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if showFeedback && isCorrect {
                    advance()
                }
            }
        } else {
            wrongAnswers += 1
            item.performance.recordFailure()
        }
        
        saveContext()
    }
    
    func revealAndFail() {
        isTextFieldFocused = false
        hintLevel = 3
        isCorrect = false
        wrongAnswers += 1
        
        hapticManager.warning()
        showFeedback = true
        
        if let item = currentItem {
            item.performance.recordFailure()
            saveContext()
        }
    }
    
    func requestHint() {
        hintLevel += 1
        hapticManager.lightImpact()
    }
    
    func skipQuestion() {
        guard let item = currentItem else { return }
        
        skippedCount += 1
        item.performance.dueDate = Date().addingTimeInterval(3600)
        
        hapticManager.selection()
        saveContext()
        advanceWithoutFeedback()
    }
    
    func advance() {
        guard !quizItems.isEmpty else { return }
        
        if currentIndex >= quizItems.count - 1 {
            showCompletionSheet = true
        } else {
            showFeedback = false
            userInput = ""
            hintLevel = 0
            currentIndex += 1
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                isTextFieldFocused = true
            }
        }
    }
    
    func reviewSkippedQuestions() {
        let hourAgo = Date().addingTimeInterval(-3600)
        let skippedItems = quizItems.filter { item in
            return item.performance.dueDate > hourAgo && item.performance.dueDate < Date().addingTimeInterval(7200)
        }
        
        if !skippedItems.isEmpty {
            currentIndex = 0
            quizItems = skippedItems
            score = 0
            skippedCount = 0
            showFeedback = false
            userInput = ""
            hintLevel = 0
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                isTextFieldFocused = true
            }
        }
    }
    
    // MARK: - Private Helpers
    private func getOrCreatePerformance(for contact: Contact) -> QuizPerformance {
        if let existing = contact.quizPerformance {
            return existing
        }
        
        let performance = QuizPerformance(contact: contact)
        modelContext.insert(performance)
        contact.quizPerformance = performance
        saveContext()
        
        return performance
    }
    
    private func calculateQuality() -> Int {
        switch hintLevel {
        case 0: return 5
        case 1: return 4
        case 2: return 3
        default: return 2
        }
    }
    
    private func calculateAutoAdvanceDelay() -> Double {
        // Longer delay for longer names or perfect scores
        let baseDelay: Double = 1.0
        let nameBonus = min(0.3, Double(correctName.count) * 0.03)
        let qualityBonus = hintLevel == 0 ? 0.2 : 0.0
        
        return baseDelay + nameBonus + qualityBonus
    }
    
    private func isAnswerCorrect(userAnswer: String, correctName: String) -> Bool {
        let normalizedUser = userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCorrect = correctName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !normalizedUser.isEmpty else { return false }
        
        if normalizedUser == normalizedCorrect {
            return true
        }
        
        let distance = levenshteinDistance(normalizedUser, normalizedCorrect)
        let threshold = max(1, normalizedCorrect.count / 4)
        return distance <= threshold
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2Array.count + 1), count: s1Array.count + 1)
        
        for i in 0...s1Array.count {
            matrix[i][0] = i
        }
        for j in 0...s2Array.count {
            matrix[0][j] = j
        }
        
        for i in 1...s1Array.count {
            for j in 1...s2Array.count {
                if s1Array[i-1] == s2Array[j-1] {
                    matrix[i][j] = matrix[i-1][j-1]
                } else {
                    matrix[i][j] = min(
                        matrix[i-1][j] + 1,
                        matrix[i][j-1] + 1,
                        matrix[i-1][j-1] + 1
                    )
                }
            }
        }
        
        return matrix[s1Array.count][s2Array.count]
    }
    
    private func advanceWithoutFeedback() {
        guard !quizItems.isEmpty else {
            showCompletionSheet = true
            return
        }
        
        if currentIndex >= quizItems.count - 1 {
            showCompletionSheet = true
        } else {
            userInput = ""
            hintLevel = 0
            currentIndex += 1
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                isTextFieldFocused = true
            }
        }
    }
    
    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("❌ [QuizViewModel] Failed to save context: \(error)")
        }
    }
}