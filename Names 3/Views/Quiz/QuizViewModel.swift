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
    var showCorrectionSheet: Bool = false
    var potentialCorrectAnswer: String = ""
    
    // MARK: - Dependencies
    private let modelContext: ModelContext
    private let hapticManager = HapticManager.shared
    private var currentSession: QuizSession?
    
    // MARK: - Computed Properties
    var currentItem: QuizItem? {
        guard currentIndex >= 0 && currentIndex < quizItems.count else { return nil }
        return quizItems[currentIndex]
    }
    
    var hasAnsweredAnyQuestion: Bool {
        return score > 0 || wrongAnswers > 0 || skippedCount > 0
    }
    
    var correctName: String {
        currentItem?.contact.displayName ?? ""
    }
    
    var allAcceptableAnswers: [String] {
        currentItem?.contact.allAcceptableNames ?? []
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
    
    // MARK: - Session Management
    func hasSavedSession() -> Bool {
        guard let session = fetchCurrentSession() else { return false }
        let hoursSinceUpdate = Date().timeIntervalSince(session.lastUpdated) / 3600
        return hoursSinceUpdate < 24 && session.currentIndex < session.contactIDs.count
    }
    
    func resumeSession() -> Bool {
        guard let session = fetchCurrentSession() else { return false }
        
        var descriptor = FetchDescriptor<Contact>()
        guard let allContacts = try? modelContext.fetch(descriptor) else { return false }
        
        let contactMap = Dictionary(uniqueKeysWithValues: allContacts.map { ($0.uuid, $0) })
        let resumedContacts = session.contactIDs.compactMap { contactMap[$0] }
        
        guard resumedContacts.count == session.contactIDs.count else {
            clearSession()
            return false
        }
        
        var items: [QuizItem] = []
        for contact in resumedContacts {
            let performance = getOrCreatePerformance(for: contact)
            items.append(QuizItem(contact: contact, performance: performance))
        }
        
        quizItems = items
        currentIndex = session.currentIndex
        score = session.score
        wrongAnswers = session.wrongAnswers
        skippedCount = session.skippedCount
        currentSession = session
        
        return true
    }
    
    func clearSession() {
        if let session = currentSession ?? fetchCurrentSession() {
            modelContext.delete(session)
            currentSession = nil
            saveContext()
        }
    }
    
    private func fetchCurrentSession() -> QuizSession? {
        var descriptor = FetchDescriptor<QuizSession>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        
        return try? modelContext.fetch(descriptor).first
    }
    
    private func saveSessionState() {
        let contactIDs = quizItems.map { $0.contact.uuid }
        
        if let session = currentSession {
            session.updateProgress(
                currentIndex: currentIndex,
                score: score,
                wrongAnswers: wrongAnswers,
                skippedCount: skippedCount
            )
        } else {
            let session = QuizSession(
                contactIDs: contactIDs,
                currentIndex: currentIndex,
                score: score,
                wrongAnswers: wrongAnswers,
                skippedCount: skippedCount
            )
            modelContext.insert(session)
            currentSession = session
        }
        
        saveContext()
    }
    
    // MARK: - Setup
    func setupQuiz(with contacts: [Contact]) {
        let valid = contacts.filter { contact in
            let hasName = !contact.displayName.isEmpty && contact.displayName != "Unnamed"
            
            let hasPhoto = !contact.photo.isEmpty && UIImage(data: contact.photo) != nil
            let hasSummary = !(contact.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            
            return hasName && (hasPhoto || hasSummary)
        }
        
        var items: [QuizItem] = []
        for contact in valid {
            let performance = getOrCreatePerformance(for: contact)
            items.append(QuizItem(contact: contact, performance: performance))
        }
        
        let selectedItems = selectQuizItems(from: items)
        quizItems = selectedItems.shuffled()
        
        saveSessionState()
    }
    
    /// Intelligent quiz item selection that balances spaced repetition with variety
    private func selectQuizItems(from items: [QuizItem]) -> [QuizItem] {
        guard !items.isEmpty else { return [] }
        
        let now = Date()
        let sessionSize = min(10, items.count)
        
        let due = items.filter { $0.performance.dueDate <= now }
        let notDue = items.filter { $0.performance.dueDate > now }
        
        var selected: [QuizItem] = []
        
        if due.count >= sessionSize {
            let sorted = due.sorted { lhs, rhs in
                let lhsScore = calculatePriorityScore(for: lhs, now: now)
                let rhsScore = calculatePriorityScore(for: rhs, now: now)
                return lhsScore > rhsScore
            }
            
            let topCount = min(sessionSize * 2, sorted.count)
            let topCandidates = Array(sorted.prefix(topCount))
            selected = Array(topCandidates.shuffled().prefix(sessionSize))
        } else {
            selected.append(contentsOf: due)
            
            let remaining = sessionSize - selected.count
            if remaining > 0 && !notDue.isEmpty {
                let sorted = notDue.sorted { lhs, rhs in
                    let lhsScore = calculatePriorityScore(for: lhs, now: now)
                    let rhsScore = calculatePriorityScore(for: rhs, now: now)
                    return lhsScore > rhsScore
                }
                
                let candidateCount = min(remaining * 2, sorted.count)
                let candidates = Array(sorted.prefix(candidateCount))
                let additionalItems = Array(candidates.shuffled().prefix(remaining))
                selected.append(contentsOf: additionalItems)
            }
        }
        
        return selected
    }
    
    /// Calculate priority score for quiz item selection
    /// Higher score = higher priority for inclusion
    private func calculatePriorityScore(for item: QuizItem, now: Date) -> Double {
        var score: Double = 0
        
        let daysSinceDue = now.timeIntervalSince(item.performance.dueDate) / 86400
        if daysSinceDue > 0 {
            score += daysSinceDue * 10
        }
        
        let inverseEaseFactor = 1.0 / Double(item.performance.easeFactor)
        score += inverseEaseFactor * 8
        
        if let lastQuizzed = item.performance.lastQuizzedDate {
            let daysSinceLastReview = now.timeIntervalSince(lastQuizzed) / 86400
            score += daysSinceLastReview * 2
        } else {
            score += 20
        }
        
        if item.performance.repetitions == 0 {
            score += 15
        } else if item.performance.repetitions < 2 {
            score += 5
        }
        
        let randomFactor = Double.random(in: 0...10)
        score += randomFactor
        
        return score
    }
    
    // MARK: - Quiz Actions
    func submitAnswer() {
        guard let item = currentItem else { return }
        
        isTextFieldFocused = false
        
        let answerResult = checkAnswer(userAnswer: userInput, acceptableNames: allAcceptableAnswers)
        isCorrect = answerResult.isCorrect
        
        if !answerResult.isCorrect {
            potentialCorrectAnswer = userInput
            hapticManager.warning()
            showCorrectionSheet = true
            return
        }
        
        hapticManager.success()
        showFeedback = true
        
        if isCorrect && hintLevel < 3 {
            score += 1
            let quality = calculateQuality()
            item.performance.recordSuccess(quality: quality)
            
            saveSessionState()
            
            let delay = calculateAutoAdvanceDelay()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if showFeedback && isCorrect {
                    advance()
                }
            }
        }
        
        saveContext()
    }
    
    func markAsCorrect() {
        guard let item = currentItem else { return }
        
        showCorrectionSheet = false
        isCorrect = true
        
        hapticManager.success()
        showFeedback = true
        
        if hintLevel < 3 {
            score += 1
            let quality = calculateQuality()
            item.performance.recordSuccess(quality: quality)
            
            saveSessionState()
            
            let delay = calculateAutoAdvanceDelay()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if showFeedback && isCorrect {
                    advance()
                }
            }
        }
        
        saveContext()
    }
    
    func markAsCorrectAndSave() {
        guard let item = currentItem else { return }
        
        let trimmedAnswer = potentialCorrectAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAnswer.isEmpty {
            var nicks = item.contact.nicknames ?? []
            if !nicks.contains(trimmedAnswer) {
                nicks.append(trimmedAnswer)
                item.contact.nicknames = nicks
            }
        }
        
        showCorrectionSheet = false
        isCorrect = true
        
        hapticManager.success()
        showFeedback = true
        
        if hintLevel < 3 {
            score += 1
            let quality = calculateQuality()
            item.performance.recordSuccess(quality: quality)
            
            saveSessionState()
            
            let delay = calculateAutoAdvanceDelay()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if showFeedback && isCorrect {
                    advance()
                }
            }
        }
        
        saveContext()
    }
    
    func markAsCorrectAndSaveAsPrimaryName() {
        guard let item = currentItem else { return }
        
        let trimmedAnswer = potentialCorrectAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAnswer.isEmpty {
            let oldName = item.contact.displayName
            
            var nicks = item.contact.nicknames ?? []
            if !nicks.contains(oldName) {
                nicks.append(oldName)
            }
            
            item.contact.name = trimmedAnswer
            item.contact.nicknames = nicks
        }
        
        showCorrectionSheet = false
        isCorrect = true
        
        hapticManager.success()
        showFeedback = true
        
        if hintLevel < 3 {
            score += 1
            let quality = calculateQuality()
            item.performance.recordSuccess(quality: quality)
            
            saveSessionState()
            
            let delay = calculateAutoAdvanceDelay()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if showFeedback && isCorrect {
                    advance()
                }
            }
        }
        
        saveContext()
    }
    
    func markAsIncorrect() {
        guard let item = currentItem else { return }
        
        showCorrectionSheet = false
        isCorrect = false
        
        hapticManager.error()
        showFeedback = true
        wrongAnswers += 1
        item.performance.recordFailure()
        saveSessionState()
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
            saveSessionState()
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
        
        hapticManager.selectionChanged()
        saveSessionState()
        saveContext()
        advanceWithoutFeedback()
    }
    
    func advance() {
        guard !quizItems.isEmpty else { return }
        
        if currentIndex >= quizItems.count - 1 {
            clearSession()
            showCompletionSheet = true
        } else {
            showFeedback = false
            userInput = ""
            hintLevel = 0
            currentIndex += 1
            saveSessionState()
            
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
            quizItems = skippedItems.shuffled()
            score = 0
            skippedCount = 0
            showFeedback = false
            userInput = ""
            hintLevel = 0
            clearSession()
            saveSessionState()
            
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
        let baseDelay: Double = 1.0
        let nameBonus = min(0.3, Double(correctName.count) * 0.03)
        let qualityBonus = hintLevel == 0 ? 0.2 : 0.0
        
        return baseDelay + nameBonus + qualityBonus
    }
    
    private struct AnswerResult {
        let isCorrect: Bool
        let isPartialMatch: Bool
    }
    
    private func checkAnswer(userAnswer: String, acceptableNames: [String]) -> AnswerResult {
        let normalizedUser = userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !normalizedUser.isEmpty else {
            return AnswerResult(isCorrect: false, isPartialMatch: false)
        }
        
        for acceptableName in acceptableNames {
            let normalizedAcceptable = acceptableName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            if normalizedUser == normalizedAcceptable {
                return AnswerResult(isCorrect: true, isPartialMatch: false)
            }
            
            let distance = levenshteinDistance(normalizedUser, normalizedAcceptable)
            let threshold = max(1, normalizedAcceptable.count / 4)
            
            if distance <= threshold {
                return AnswerResult(isCorrect: true, isPartialMatch: false)
            }
        }
        
        for acceptableName in acceptableNames {
            let normalizedAcceptable = acceptableName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let userWords = normalizedUser.split(separator: " ").map(String.init)
            let acceptableWords = normalizedAcceptable.split(separator: " ").map(String.init)
            
            if acceptableWords.count > 1 {
                for userWord in userWords {
                    for acceptableWord in acceptableWords {
                        if userWord == acceptableWord && userWord.count >= 2 {
                            return AnswerResult(isCorrect: false, isPartialMatch: true)
                        }
                        
                        let distance = levenshteinDistance(userWord, acceptableWord)
                        let threshold = max(1, acceptableWord.count / 3)
                        
                        if distance <= threshold && userWord.count >= 3 {
                            return AnswerResult(isCorrect: false, isPartialMatch: true)
                        }
                    }
                }
            }
        }
        
        return AnswerResult(isCorrect: false, isPartialMatch: false)
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
            clearSession()
            showCompletionSheet = true
            return
        }
        
        if currentIndex >= quizItems.count - 1 {
            clearSession()
            showCompletionSheet = true
        } else {
            userInput = ""
            hintLevel = 0
            currentIndex += 1
            saveSessionState()
            
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