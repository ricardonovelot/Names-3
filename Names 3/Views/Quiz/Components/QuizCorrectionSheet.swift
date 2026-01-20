import SwiftUI

struct QuizCorrectionSheet: View {
    let userAnswer: String
    let expectedAnswer: String
    let allAcceptableAnswers: [String]
    let onMarkCorrect: () -> Void
    let onMarkCorrectAndSaveAsNickname: () -> Void
    let onMarkCorrectAndSaveAsPrimaryName: () -> Void
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
            
            Text("Choose how to handle this answer variation.")
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
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Button {
                    onMarkCorrect()
                    dismiss()
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Accept (This Time)")
                        }
                        .font(isIPad ? .title3.weight(.semibold) : .body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, isIPad ? 18 : 16)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                
                Text("Count as correct but don't save")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            
            VStack(spacing: 8) {
                Text("Save Options")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(spacing: 12) {
                    Button {
                        onMarkCorrectAndSaveAsNickname()
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.plus.fill")
                                Text("Save as Nickname")
                            }
                            .font(isIPad ? .title3.weight(.semibold) : .body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, isIPad ? 18 : 16)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    
                    Text("Add '\(userAnswer)' as an alternate name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    
                    Button {
                        onMarkCorrectAndSaveAsPrimaryName()
                        dismiss()
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill.badge.checkmark")
                                Text("Save as Primary Name")
                            }
                            .font(isIPad ? .title3.weight(.semibold) : .body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, isIPad ? 18 : 16)
                        .background(Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    
                    Text("Make '\(userAnswer)' the main name (moves '\(expectedAnswer)' to nicknames)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            Button {
                onMarkIncorrect()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                    Text("I Was Wrong")
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