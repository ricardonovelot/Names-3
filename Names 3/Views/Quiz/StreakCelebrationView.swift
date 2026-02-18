import SwiftUI

/// Shows the user's persistence and consistency when they tap their streak on the Practice menu.
struct StreakCelebrationView: View {
    let kind: QuizKind
    let accentColor: Color
    let onDismiss: () -> Void
    
    private let streakManager = QuizStreakManager.shared
    private let reminderService = QuizReminderService.shared
    
    @State private var isDailyReminderEnabled: Bool = false
    
    private var modeTitle: String {
        switch kind {
        case .faces: return "Face Quiz"
        case .notes: return "Memory Rehearsal"
        }
    }
    
    private var streakCount: Int { streakManager.currentStreak(for: kind) }
    private var totalQuizzes: Int { streakManager.totalQuizzes(for: kind) }
    private var bestScore: Int { streakManager.bestScore(for: kind) }
    private var lastDate: Date? { streakManager.lastQuizDate(for: kind) }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 24)
                        
                        modeHeader
                        
                        persistenceStats
                        
                        if let last = lastDate {
                            lastPracticeRow(date: last)
                        }
                        
                        dailyReminderSection
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Consistency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                isDailyReminderEnabled = reminderService.isDailyReminderEnabled
            }
        }
    }
    
    private var modeHeader: some View {
        VStack(spacing: 8) {
            Text(modeTitle)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            
            Text("How consistently you've practiced")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
    
    private var persistenceStats: some View {
        VStack(spacing: 12) {
            statRow(
                icon: "flame.fill",
                label: "Current streak",
                value: streakCount > 0 ? "\(streakCount) day\(streakCount == 1 ? "" : "s") in a row" : "No streak yet",
                valueColor: streakCount > 0 ? accentColor : .secondary
            )
            
            statRow(
                icon: "checkmark.circle.fill",
                label: "Sessions completed",
                value: "\(totalQuizzes)",
                valueColor: .primary
            )
            
            if bestScore > 0 {
                statRow(
                    icon: "star.fill",
                    label: "Best score",
                    value: "\(bestScore)%",
                    valueColor: .primary
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private func statRow(icon: String, label: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(accentColor)
                .frame(width: 24, alignment: .center)
            
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer(minLength: 8)
            
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(valueColor)
        }
        .padding(.vertical, 4)
    }
    
    private func lastPracticeRow(date: Date) -> some View {
        HStack {
            Image(systemName: "calendar")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Text("Last practiced \(date.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private var dailyReminderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily reminder")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            
            Text("Get a notification every day at 9:00 AM to practice and keep your streak going.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Toggle(isOn: $isDailyReminderEnabled) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(accentColor)
                    Text("Remind me every day")
                        .font(.subheadline)
                }
            }
            .onChange(of: isDailyReminderEnabled) { _, newValue in
                if newValue {
                    reminderService.enableAndScheduleDailyReminder()
                } else {
                    reminderService.disableDailyReminder()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    StreakCelebrationView(kind: .faces, accentColor: .blue) {}
}
