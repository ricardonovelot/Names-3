import Foundation

final class QuizStreakManager {
    static let shared = QuizStreakManager()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let currentStreak = "quiz_current_streak"
        static let lastQuizDate = "quiz_last_date"
        static let bestScore = "quiz_best_score"
        static let totalQuizzes = "quiz_total_count"
    }
    
    private init() {}
    
    var currentStreak: Int {
        get { defaults.integer(forKey: Keys.currentStreak) }
        set { defaults.set(newValue, forKey: Keys.currentStreak) }
    }
    
    var lastQuizDate: Date? {
        get { defaults.object(forKey: Keys.lastQuizDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastQuizDate) }
    }
    
    var bestScore: Int {
        get { defaults.integer(forKey: Keys.bestScore) }
        set { defaults.set(newValue, forKey: Keys.bestScore) }
    }
    
    var totalQuizzes: Int {
        get { defaults.integer(forKey: Keys.totalQuizzes) }
        set { defaults.set(newValue, forKey: Keys.totalQuizzes) }
    }
    
    // Only call this when user completes the full quiz (not partial sessions)
    func recordQuizCompletion(score: Int, totalQuestions: Int, isFullCompletion: Bool) {
        guard isFullCompletion else {
            // Don't update streak or stats for partial sessions
            return
        }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Update streak
        if let lastDate = lastQuizDate {
            let lastDay = calendar.startOfDay(for: lastDate)
            let daysDifference = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
            
            if daysDifference == 0 {
                // Same day, don't increment streak
            } else if daysDifference == 1 {
                // Consecutive day, increment
                currentStreak += 1
            } else {
                // Streak broken, reset to 1
                currentStreak = 1
            }
        } else {
            // First quiz ever
            currentStreak = 1
        }
        
        lastQuizDate = Date()
        totalQuizzes += 1
        
        // Update best score (percentage)
        let percentage = totalQuestions > 0 ? Int((Double(score) / Double(totalQuestions)) * 100) : 0
        if percentage > bestScore {
            bestScore = percentage
        }
    }
    
    func daysSinceLastQuiz() -> Int? {
        guard let lastDate = lastQuizDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDay = calendar.startOfDay(for: lastDate)
        return calendar.dateComponents([.day], from: lastDay, to: today).day
    }
    
    func isNewBestScore(score: Int, totalQuestions: Int) -> Bool {
        guard totalQuestions > 0 else { return false }
        let percentage = Int((Double(score) / Double(totalQuestions)) * 100)
        return percentage > bestScore
    }
}