import SwiftUI

struct QuizCorrectionSheet: View {
    let userAnswer: String
    let expectedAnswer: String
    let allAcceptableAnswers: [String]
    let onMarkCorrect: () -> Void
    let onMarkIncorrect: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                headerSection
                
                answersSection
                
                Spacer()
                
                actionButtons
            }
            .padding(24)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Verify Answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            
            Text("Was your answer correct?")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            
            Text("Your answer was close but didn't match exactly. If it's another name they go by, mark it as correct.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    @ViewBuilder
    private var answersSection: some View {
        VStack(spacing: 16) {
            answerCard(
                title: "You entered",
                answer: userAnswer,
                icon: "person.fill.questionmark",
                color: .orange
            )
            
            answerCard(
                title: "Expected answers",
                answer: allAcceptableAnswers.isEmpty ? expectedAnswer : allAcceptableAnswers.joined(separator: " • "),
                icon: "checkmark.circle.fill",
                color: .green
            )
        }
    }
    
    @ViewBuilder
    private func answerCard(title: String, answer: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
            }
            
            Text(answer)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                onMarkCorrect()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Yes, I Was Correct")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            
            Button {
                onMarkIncorrect()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("No, I Was Wrong")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}