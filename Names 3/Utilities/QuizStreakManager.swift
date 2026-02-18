import Foundation

/// Identifies which practice mode a streak applies to. Used for per-mode streak storage.
enum QuizKind: String, CaseIterable {
    case faces
    case notes
}

final class QuizStreakManager {
    static let shared = QuizStreakManager()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let currentStreak = "quiz_current_streak"
        static let lastQuizDate = "quiz_last_date"
        static let bestScore = "quiz_best_score"
        static let totalQuizzes = "quiz_total_count"
        static func streak(_ kind: QuizKind) -> String { "quiz_streak_\(kind.rawValue)" }
        static func lastDate(_ kind: QuizKind) -> String { "quiz_last_date_\(kind.rawValue)" }
        static func bestScore(_ kind: QuizKind) -> String { "quiz_best_score_\(kind.rawValue)" }
        static func totalCount(_ kind: QuizKind) -> String { "quiz_total_count_\(kind.rawValue)" }
    }
    
    private init() {}
    
    // MARK: - Legacy (single) API — forwards to .faces for backward compatibility
    
    var currentStreak: Int {
        get { currentStreak(for: .faces) }
        set { setCurrentStreak(newValue, for: .faces) }
    }
    
    var lastQuizDate: Date? {
        get { lastQuizDate(for: .faces) }
        set { setLastQuizDate(newValue, for: .faces) }
    }
    
    var bestScore: Int {
        get { bestScore(for: .faces) }
        set { setBestScore(newValue, for: .faces) }
    }
    
    var totalQuizzes: Int {
        get { totalQuizzes(for: .faces) }
        set { setTotalQuizzes(newValue, for: .faces) }
    }
    
    /// Continuous days of completing this quiz type. Use for UI (e.g. Practice menu).
    /// Returns 0 if the streak is broken (last practice was more than 1 day ago).
    func currentStreak(for kind: QuizKind) -> Int {
        migrateLegacyToFacesIfNeeded()
        guard let last = lastQuizDate(for: kind) else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDay = calendar.startOfDay(for: last)
        let daysSince = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        if daysSince == 0 || daysSince == 1 {
            return defaults.integer(forKey: Keys.streak(kind))
        }
        return 0
    }
    
    private func setCurrentStreak(_ value: Int, for kind: QuizKind) {
        defaults.set(value, forKey: Keys.streak(kind))
    }
    
    func lastQuizDate(for kind: QuizKind) -> Date? {
        migrateLegacyToFacesIfNeeded()
        return defaults.object(forKey: Keys.lastDate(kind)) as? Date
    }
    
    private func setLastQuizDate(_ value: Date?, for kind: QuizKind) {
        defaults.set(value, forKey: Keys.lastDate(kind))
    }
    
    func bestScore(for kind: QuizKind) -> Int {
        migrateLegacyToFacesIfNeeded()
        return defaults.integer(forKey: Keys.bestScore(kind))
    }
    
    private func setBestScore(_ value: Int, for kind: QuizKind) {
        defaults.set(value, forKey: Keys.bestScore(kind))
    }
    
    func totalQuizzes(for kind: QuizKind) -> Int {
        migrateLegacyToFacesIfNeeded()
        return defaults.integer(forKey: Keys.totalCount(kind))
    }
    
    private func setTotalQuizzes(_ value: Int, for kind: QuizKind) {
        defaults.set(value, forKey: Keys.totalCount(kind))
    }
    
    /// One-time migration: copy legacy single streak/lastDate into .faces so existing users keep their face quiz streak.
    private func migrateLegacyToFacesIfNeeded() {
        let migratedKey = "quiz_streak_migrated_to_per_kind"
        if defaults.bool(forKey: migratedKey) { return }
        let legacyStreak = defaults.integer(forKey: Keys.currentStreak)
        let legacyDate = defaults.object(forKey: Keys.lastQuizDate) as? Date
        let legacyBest = defaults.integer(forKey: Keys.bestScore)
        let legacyTotal = defaults.integer(forKey: Keys.totalQuizzes)
        if legacyStreak > 0 || legacyDate != nil || legacyBest > 0 || legacyTotal > 0 {
            defaults.set(legacyStreak, forKey: Keys.streak(.faces))
            defaults.set(legacyDate, forKey: Keys.lastDate(.faces))
            defaults.set(legacyBest, forKey: Keys.bestScore(.faces))
            defaults.set(legacyTotal, forKey: Keys.totalCount(.faces))
        }
        defaults.set(true, forKey: migratedKey)
    }
    
    // Only call this when user completes the full quiz (not partial sessions).
    /// Records completion for a specific quiz kind and updates that kind's streak and stats.
    func recordQuizCompletion(quizKind kind: QuizKind, score: Int, totalQuestions: Int, isFullCompletion: Bool) {
        guard isFullCompletion else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDate = lastQuizDate(for: kind)
        var streak = currentStreak(for: kind)
        
        if let last = lastDate {
            let lastDay = calendar.startOfDay(for: last)
            let daysDifference = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if daysDifference == 0 {
                // Same day, no change to streak
            } else if daysDifference == 1 {
                streak += 1
            } else {
                streak = 1
            }
        } else {
            streak = 1
        }
        
        setCurrentStreak(streak, for: kind)
        setLastQuizDate(Date(), for: kind)
        setTotalQuizzes(totalQuizzes(for: kind) + 1, for: kind)
        
        let percentage = totalQuestions > 0 ? Int((Double(score) / Double(totalQuestions)) * 100) : 0
        if percentage > bestScore(for: kind) {
            setBestScore(percentage, for: kind)
        }
    }
    
    /// Legacy entry point: records completion for Face Quiz only (backward compatibility).
    func recordQuizCompletion(score: Int, totalQuestions: Int, isFullCompletion: Bool) {
        recordQuizCompletion(quizKind: .faces, score: score, totalQuestions: totalQuestions, isFullCompletion: isFullCompletion)
    }
    
    func daysSinceLastQuiz() -> Int? {
        daysSinceLastQuiz(for: .faces)
    }
    
    func daysSinceLastQuiz(for kind: QuizKind) -> Int? {
        guard let lastDate = lastQuizDate(for: kind) else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDay = calendar.startOfDay(for: lastDate)
        return calendar.dateComponents([.day], from: lastDay, to: today).day
    }
    
    func isNewBestScore(score: Int, totalQuestions: Int) -> Bool {
        guard totalQuestions > 0 else { return false }
        let percentage = Int((Double(score) / Double(totalQuestions)) * 100)
        return percentage > bestScore(for: .faces)
    }
    
    func isNewBestScore(score: Int, totalQuestions: Int, for kind: QuizKind) -> Bool {
        guard totalQuestions > 0 else { return false }
        let percentage = Int((Double(score) / Double(totalQuestions)) * 100)
        return percentage > bestScore(for: kind)
    }
}