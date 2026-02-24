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
    @State private var contentVisible = false
    
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
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 12)
                }
                
                if showConfetti {
                    ConfettiView()
                        .allowsHitTesting(false)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionButtons
                    .opacity(contentVisible ? 1 : 0)
                    .background(.thinMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if isFullCompletion && streakManager.currentStreak > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("\(streakManager.currentStreak) day streak")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear {
            recordCompletion()
            
            withAnimation(.easeOut(duration: 0.45)) {
                contentVisible = true
            }
            
            if isPerfectScore || isNewBest {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                    showConfetti = true
                }
            }
            
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
        VStack(spacing: 14) {
            Image(systemName: performanceIcon)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(iconColor)
                .symbolEffect(.bounce, value: showConfetti)
            
            Text(performanceMessage)
                .font(.system(size: 24, weight: .semibold))
            
            if questionsAttempted > 0 {
                VStack(spacing: 6) {
                    if isFullCompletion {
                        Text("\(correctAnswers) of \(totalQuestions) correct")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(questionsAttempted) of \(totalQuestions) attempted")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if isNewBest {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                            Text("Personal record")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color(UIColor.tertiarySystemFill))
                        .clipShape(Capsule())
                    }
                }
            } else {
                Text("No questions attempted")
                    .font(.subheadline)
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if skippedCount > 0 && isFullCompletion {
                Button {
                    onReview()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.subheadline.weight(.medium))
                        Text("Review Skipped (\(skippedCount))")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            
            Button {
                onDismiss()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
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