import SwiftUI

struct QuizCompletionView: View {
    let totalQuestions: Int
    let correctAnswers: Int
    let wrongAnswers: Int
    let skippedCount: Int
    let isFullCompletion: Bool
    let onReview: () -> Void
    let onDismiss: () -> Void
    
    @State private var showConfetti = false
    @State private var autoDismissTimer: Timer?
    
    private let streakManager = QuizStreakManager.shared
    
    private var questionsAttempted: Int {
        correctAnswers + wrongAnswers
    }
    
    private var accuracy: Double {
        guard questionsAttempted > 0 else { return 0 }
        return Double(correctAnswers) / Double(questionsAttempted)
    }
    
    private var isPerfectScore: Bool {
        isFullCompletion && accuracy == 1.0 && skippedCount == 0 && questionsAttempted > 0
    }
    
    private var isNewBest: Bool {
        guard isFullCompletion else { return false }
        return streakManager.isNewBestScore(score: correctAnswers, totalQuestions: totalQuestions)
    }
    
    private var performanceMessage: String {
        if !isFullCompletion {
            if questionsAttempted == 0 {
                return "Come Back Soon"
            }
            return "Keep Going!"
        }
        
        if isPerfectScore {
            return "Perfect!"
        } else if isNewBest {
            return "New Best!"
        } else if accuracy >= 0.8 {
            return "Excellent!"
        } else if accuracy >= 0.6 {
            return "Great Work!"
        } else {
            return "Keep Practicing!"
        }
    }
    
    private var performanceIcon: String {
        if !isFullCompletion {
            return questionsAttempted == 0 ? "arrow.clockwise" : "flag.checkered"
        }
        
        if isPerfectScore {
            return "star.circle.fill"
        } else if isNewBest {
            return "trophy.fill"
        } else if accuracy >= 0.8 {
            return "checkmark.seal.fill"
        } else {
            return "hand.thumbsup.fill"
        }
    }
    
    private var iconColor: Color {
        if !isFullCompletion {
            return .orange
        }
        
        if isPerfectScore || isNewBest {
            return .yellow
        } else if accuracy >= 0.8 {
            return .green
        } else if accuracy >= 0.6 {
            return .blue
        } else {
            return .orange
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 40)
                        
                        heroSection
                        
                        if questionsAttempted > 0 {
                            statsSection
                        }
                        
                        if isFullCompletion, let days = streakManager.daysSinceLastQuiz(), days > 1 {
                            welcomeBackCard(days: days)
                        }
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
                
                if showConfetti {
                    ConfettiView()
                        .allowsHitTesting(false)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionButtons
                    .background(.ultraThinMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isFullCompletion && streakManager.currentStreak > 0 {
                        HStack(spacing: 6) {
                            Text("🔥")
                                .font(.body)
                            Text("\(streakManager.currentStreak) day streak")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
        .onAppear {
            recordCompletion()
            
            if isPerfectScore || isNewBest {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    showConfetti = true
                }
            }
            
            // Auto-dismiss on perfect score
            if isPerfectScore {
                autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                    onDismiss()
                }
            }
        }
        .onDisappear {
            autoDismissTimer?.invalidate()
        }
    }
    
    @ViewBuilder
    private var heroSection: some View {
        VStack(spacing: 16) {
            Image(systemName: performanceIcon)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(iconColor)
                .symbolEffect(.bounce, value: showConfetti)
                .padding(.bottom, 4)
            
            Text(performanceMessage)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            
            if questionsAttempted > 0 {
                VStack(spacing: 4) {
                    if isFullCompletion {
                        Text("\(correctAnswers) of \(totalQuestions)")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Attempted \(questionsAttempted) of \(totalQuestions)")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    if isNewBest {
                        Text("🎉 Personal Record!")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(.yellow.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            } else {
                Text("No questions attempted")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var statsSection: some View {
        VStack(spacing: 10) {
            if correctAnswers > 0 {
                statRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    label: "Correct",
                    value: "\(correctAnswers)"
                )
            }
            
            if wrongAnswers > 0 {
                statRow(
                    icon: "xmark.circle.fill",
                    color: .red,
                    label: "Wrong",
                    value: "\(wrongAnswers)"
                )
            }
            
            if skippedCount > 0 {
                statRow(
                    icon: "arrow.forward.circle.fill",
                    color: .orange,
                    label: "Skipped",
                    value: "\(skippedCount)"
                )
            }
            
            if !isFullCompletion && questionsAttempted < totalQuestions {
                statRow(
                    icon: "pause.circle.fill",
                    color: .gray,
                    label: "Not Attempted",
                    value: "\(totalQuestions - questionsAttempted - skippedCount)"
                )
            }
            
            if questionsAttempted > 0 {
                Divider()
                    .padding(.vertical, 4)
                
                statRow(
                    icon: "percent",
                    color: .blue,
                    label: "Accuracy",
                    value: "\(Int(accuracy * 100))%",
                    prominent: true
                )
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @ViewBuilder
    private func statRow(icon: String, color: Color, label: String, value: String, prominent: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: prominent ? 20 : 18))
                .foregroundStyle(color)
                .frame(width: 28)
            
            Text(label)
                .font(prominent ? .body.weight(.semibold) : .body)
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text(value)
                .font(prominent ? .title3.weight(.bold) : .body.weight(.medium))
                .foregroundStyle(prominent ? color : .secondary)
        }
    }
    
    @ViewBuilder
    private func welcomeBackCard(days: Int) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.wave.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            
            Text(days == 1 ? "Welcome back!" : "Long time no see!")
                .font(.headline)
            
            Text(days == 1 ? "Your last quiz was yesterday" : "Last quiz was \(days) days ago")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if skippedCount > 0 && isFullCompletion {
                Button {
                    onReview()
                } label: {
                    HStack {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Review Skipped (\(skippedCount))")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private func recordCompletion() {
        if questionsAttempted > 0 {
            streakManager.recordQuizCompletion(
                score: correctAnswers,
                totalQuestions: totalQuestions,
                isFullCompletion: isFullCompletion
            )
        }
    }
}

// MARK: - Confetti Effect

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    
    struct ConfettiParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var color: Color
        var rotation: Double
        var scale: CGFloat
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: 8, height: 8)
                        .scaleEffect(particle.scale)
                        .rotationEffect(.degrees(particle.rotation))
                        .position(x: particle.x, y: particle.y)
                }
            }
            .onAppear {
                createConfetti(in: geometry.size)
            }
        }
    }
    
    private func createConfetti(in size: CGSize) {
        let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .pink]
        
        for _ in 0..<50 {
            let particle = ConfettiParticle(
                x: CGFloat.random(in: 0...size.width),
                y: -20,
                color: colors.randomElement() ?? .blue,
                rotation: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.5...1.5)
            )
            particles.append(particle)
        }
        
        animateConfetti(in: size)
    }
    
    private func animateConfetti(in size: CGSize) {
        for i in particles.indices {
            withAnimation(
                .easeOut(duration: Double.random(in: 1.5...3.0))
                .delay(Double.random(in: 0...0.3))
            ) {
                particles[i].y = size.height + 50
                particles[i].x += CGFloat.random(in: -100...100)
                particles[i].rotation += Double.random(in: 180...720)
            }
        }
    }
}