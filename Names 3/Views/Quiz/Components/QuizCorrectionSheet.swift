import SwiftUI

struct QuizCorrectionSheet: View {
    let userAnswer: String
    let expectedAnswer: String
    let allAcceptableAnswers: [String]
    let onMarkCorrect: () -> Void
    let onMarkIncorrect: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                        .padding(.top, 20)
                    
                    answersSection
                    
                    actionButtons
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, isIPad ? 40 : 24)
            }
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
        .presentationDetents(isIPad ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: isIPad ? 72 : 56))
                .foregroundStyle(.orange)
            
            Text("Was your answer correct?")
                .font(isIPad ? .title.bold() : .title2.bold())
                .multilineTextAlignment(.center)
            
            Text("If what you entered is another valid name or nickname for this person, mark it as correct and it will be saved.")
                .font(isIPad ? .body : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: isIPad ? 500 : .infinity)
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
        .frame(maxWidth: isIPad ? 500 : .infinity)
    }
    
    @ViewBuilder
    private func answerCard(title: String, answer: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .font(.system(size: isIPad ? 20 : 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(isIPad ? 20 : 16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                onMarkCorrect()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Yes, I Was Correct")
                }
                .font(isIPad ? .title3.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, isIPad ? 18 : 16)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            
            Button {
                onMarkIncorrect()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                    Text("No, I Was Wrong")
                }
                .font(isIPad ? .title3.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, isIPad ? 18 : 16)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .frame(maxWidth: isIPad ? 500 : .infinity)
    }
}