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
    @State private var showSaveOptions = false
    
    private var isIPad: Bool { horizontalSizeClass == .regular }
    private var expectedDisplay: String {
        allAcceptableAnswers.isEmpty ? expectedAnswer : allAcceptableAnswers.joined(separator: " • ")
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                compactAnswersRow
                compactActions
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Verify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.body.weight(.medium))
                }
            }
        }
        .presentationDetents(
            isIPad
                ? [.medium, .large]
                : (showSaveOptions ? [.height(340)] : [.height(220)])
        )
        .presentationDragIndicator(.visible)
    }
    
    private var compactAnswersRow: some View {
        HStack(spacing: 12) {
            compactChip(label: "You", value: userAnswer, color: .orange)
            Image(systemName: "arrow.left.arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            compactChip(label: "Expected", value: expectedDisplay, color: .green)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    private func compactChip(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    @ViewBuilder
    private var compactActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    onMarkCorrect()
                    dismiss()
                } label: {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Accept as correct, don't save")
                
                Button {
                    onMarkIncorrect()
                    dismiss()
                } label: {
                    Label("Wrong", systemImage: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark as incorrect")
            }
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSaveOptions.toggle()
                }
            } label: {
                HStack {
                    Text(showSaveOptions ? "Hide save options" : "Save as nickname…")
                        .font(.subheadline.weight(.medium))
                    Image(systemName: showSaveOptions ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            
            if showSaveOptions {
                VStack(spacing: 8) {
                    Button {
                        onMarkCorrectAndSaveAsNickname()
                        dismiss()
                    } label: {
                        Label("Save as Nickname", systemImage: "person.badge.plus.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        onMarkCorrectAndSaveAsPrimaryName()
                        dismiss()
                    } label: {
                        Label("Save as Primary", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.purple, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}