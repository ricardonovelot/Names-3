import SwiftUI

struct QuizProgressBar: View {
    let currentIndex: Int
    let totalQuestions: Int
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var progress: Double {
        guard totalQuestions > 0 else { return 0 }
        return Double(currentIndex) / Double(totalQuestions)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("\(min(currentIndex + 1, totalQuestions))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("of \(totalQuestions)")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Question \(currentIndex + 1) of \(totalQuestions)")
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 6)
                        .animation(
                            reduceMotion ? .linear(duration: 0.1) : .spring(response: 0.4, dampingFraction: 0.8),
                            value: progress
                        )
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}