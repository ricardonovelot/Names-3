import SwiftUI
import SwiftData
import UIKit

struct QuizView: View {
    let contacts: [Contact]
    let onComplete: () -> Void
    let onRequestExit: (() -> Bool)?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    
    @StateObject private var keyboardObserver = KeyboardHeightObserver.shared
    @State private var viewModel: QuizViewModel?
    @State private var showResumeDialog: Bool = false
    @State private var showExitConfirmation: Bool = false
    
    @Namespace private var animation
    
    /// Quiz assumes keyboard visible by default (input is first responder). Use compact layout until we know it's hidden.
    private var isCompact: Bool {
        keyboardObserver.isKeyboardVisible
    }
    
    var body: some View {
        Group {
            if let viewModel {
                quizContent(viewModel: viewModel)
            } else {
                loadingView
                    .onAppear {
                        setupViewModel()
                    }
            }
        }
    }
    
    private var loadingView: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            VStack(spacing: QuizDesign.Spacing.lg) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Preparing quiz…")
                    .font(QuizDesign.Typography.body(compact: false))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading quiz")
    }
    
    @ViewBuilder
    private func quizContent(viewModel: QuizViewModel) -> some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if let item = viewModel.currentItem {
                    VStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 0) {
                                    questionSection(item: item, viewModel: viewModel)
                                        .id("question")
                                    Spacer(minLength: isCompact ? QuizDesign.Spacing.md : QuizDesign.Spacing.xxl)
                                }
                                .contentShape(.rect)
                            }
                            .scrollDismissesKeyboard(.never)
                            .defaultScrollAnchor(.top)
                            .onChange(of: viewModel.currentIndex) { _, _ in
                                withAnimation(QuizDesign.Animation.questionTransition) {
                                    proxy.scrollTo("question", anchor: .top)
                                }
                            }
                        }
                        answerSection(viewModel: viewModel)
                    }
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("Face Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if !viewModel.quizItems.isEmpty {
                        quizToolbarProgress(currentIndex: viewModel.currentIndex, total: viewModel.quizItems.count, compact: isCompact)
                    } else {
                        Text("Face Quiz")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        performExit()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: isCompact ? 14 : 16, weight: .medium))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(.secondary)
                            .contentShape(Circle())
                            .liquidGlass(in: Circle(), stroke: true, style: .clear)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Exit quiz")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showCompletionSheet },
            set: { viewModel.showCompletionSheet = $0 }
        )) {
            QuizCompletionView(
                totalQuestions: viewModel.quizItems.count,
                correctAnswers: viewModel.score,
                wrongAnswers: viewModel.wrongAnswers,
                skippedCount: viewModel.skippedCount,
                isFullCompletion: viewModel.currentIndex >= viewModel.quizItems.count - 1,
                onReview: {
                    viewModel.showCompletionSheet = false
                    viewModel.reviewSkippedQuestions()
                },
                onDismiss: {
                    viewModel.showCompletionSheet = false
                    onComplete()
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showCorrectionSheet },
            set: { viewModel.showCorrectionSheet = $0 }
        )) {
            QuizCorrectionSheet(
                userAnswer: viewModel.potentialCorrectAnswer,
                expectedAnswer: viewModel.correctName,
                allAcceptableAnswers: viewModel.allAcceptableAnswers,
                onMarkCorrect: {
                    viewModel.markAsCorrect()
                },
                onMarkCorrectAndSaveAsNickname: {
                    viewModel.markAsCorrectAndSave()
                },
                onMarkCorrectAndSaveAsPrimaryName: {
                    viewModel.markAsCorrectAndSaveAsPrimaryName()
                },
                onMarkIncorrect: {
                    viewModel.markAsIncorrect()
                }
            )
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onShake {
            if !viewModel.showFeedback && viewModel.currentItem != nil {
                viewModel.requestHint()
            }
        }
        .accessibilityHint(voiceOverEnabled && viewModel.currentItem != nil && !viewModel.showFeedback ? "Shake device to reveal a hint" : "")
        .onDisappear {
            // Persist only true in‑progress quizzes (not completed ones)
            guard viewModel.hasAnsweredAnyQuestion else { return }
            let total = viewModel.quizItems.count
            let index = viewModel.currentIndex
            // Only save if user is somewhere before the final question
            if total > 0 && index >= 0 && index < total - 1 {
                viewModel.saveSessionState()
            }
        }
        // Resume UI dialog removed: quiz sessions are resumed silently when needed.
    }
    
    /// Question area: photo + optional context (note/group) + hint. Clear visual hierarchy.
    @ViewBuilder
    private func questionSection(item: QuizViewModel.QuizItem, viewModel: QuizViewModel) -> some View {
        VStack(alignment: .leading, spacing: QuizDesign.Spacing.content(compact: isCompact)) {
            QuizPhotoCard(contact: item.contact, preferredHeight: QuizDesign.Layout.photoHeight(compact: isCompact), compact: isCompact)
                .padding(.top, isCompact ? 4 : 12)
                .transition(cardTransition)
                .id(item.id)
            
            contextualChips(contact: item.contact, compact: isCompact)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            
            if !viewModel.showFeedback {
                hintSection(viewModel: viewModel, compact: isCompact)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, QuizDesign.Layout.horizontalPadding)
    }
    
    /// Merged summary + group as compact chips when both or either present.
    @ViewBuilder
    private func contextualChips(contact: Contact, compact: Bool) -> some View {
        let hasSummary = (contact.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasGroup = !(contact.tags?.isEmpty ?? true)
        if !hasSummary && !hasGroup {
            EmptyView()
        } else if compact {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if hasSummary {
                        chip(icon: "note.text", label: String((contact.summary ?? "").prefix(40)) + ((contact.summary ?? "").count > 40 ? "…" : ""), compact: true)
                    }
                    if hasGroup {
                        chip(icon: "person.2.fill", label: groupLabel(for: contact), compact: true)
                    }
                }
                .padding(.horizontal, 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(hasSummary && hasGroup ? "Note: \(contact.summary ?? ""). Group: \(groupLabel(for: contact))" : hasSummary ? "Note: \(contact.summary ?? "")" : "Group: \(groupLabel(for: contact))")
        } else {
            VStack(spacing: 16) {
                if hasSummary {
                    summarySection(text: contact.summary ?? "", compact: false)
                }
                if hasGroup {
                    groupSection(for: contact, compact: false)
                }
            }
        }
    }
    
    @ViewBuilder
    private func chip(icon: String, label: String, compact: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: compact ? 11 : 12))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: compact ? 13 : 14, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 6 : 8)
        .liquidGlass(in: Capsule(), stroke: true, style: .clear)
    }
    
    @ViewBuilder
    private func summarySection(text: String, compact: Bool = false) -> some View {
        let padding: CGFloat = compact ? 10 : 12
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Label {
                Text("Note")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "note.text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Text(text)
                .font(.system(size: compact ? 15 : 17, weight: .medium, design: .default))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(compact ? 2 : nil)
        }
        .padding(padding)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .padding(.horizontal, 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Note: \(text)")
    }
    
    @ViewBuilder
    private func groupSection(for contact: Contact, compact: Bool = false) -> some View {
        let padding: CGFloat = compact ? 10 : 12
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            Label {
                Text("Group")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "person.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Text(groupLabel(for: contact))
                .font(.system(size: compact ? 15 : 17, weight: .semibold, design: .default))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(padding)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.15), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .padding(.horizontal, 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Group: \(groupLabel(for: contact))")
    }
    
    /// Answer area: feedback (when shown) + input + controls. Single exit in toolbar.
    @ViewBuilder
    private func answerSection(viewModel: QuizViewModel) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 1)
            
            VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
                if viewModel.showFeedback {
                    HStack(alignment: .center, spacing: 12) {
                        inlineFeedbackBanner(viewModel: viewModel)
                            .frame(maxWidth: .infinity)
                        Button {
                            withAnimation(QuizDesign.Animation.feedbackTransition) {
                                viewModel.advance()
                            }
                        } label: {
                            HStack(spacing: QuizDesign.Spacing.xs) {
                                Text("Next")
                                Image(systemName: "arrow.right")
                                    .font(.system(size: isCompact ? 10 : 11, weight: .semibold))
                            }
                            .font(QuizDesign.Typography.bodySemibold(compact: isCompact))
                            .foregroundStyle(.white)
                            .padding(.horizontal, isCompact ? QuizDesign.Spacing.md : QuizDesign.Spacing.lg)
                            .padding(.vertical, isCompact ? QuizDesign.Spacing.sm : QuizDesign.Spacing.sm)
                            .background(Color.accentColor.gradient, in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(QuizPrimaryButtonStyle())
                        .accessibilityLabel("Next question")
                    }
                }
                
                VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
                    if !viewModel.showFeedback {
                        Text("Who is this?")
                            .font(.system(size: isCompact ? 13 : 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    QuizInputBarRepresentable(
                        text: Binding(
                            get: { viewModel.userInput },
                            set: { viewModel.userInput = $0 }
                        ),
                        placeholder: "Type their name…",
                        submitDisabled: viewModel.showFeedback,
                        focusTrigger: viewModel.currentIndex,
                        onSubmit: {
                            guard !viewModel.showFeedback else { return }
                            viewModel.submitAnswer()
                        },
                        compact: isCompact
                    )
                    .frame(height: isCompact ? 40 : 48)
                }
                
                HStack(spacing: isCompact ? 10 : 12) {
                    ScoreDisplay(score: viewModel.score, total: max(1, viewModel.currentIndex + 1), compact: isCompact)
                    Spacer()
                    if !viewModel.showFeedback {
                        Button {
                            viewModel.skipQuestion()
                        } label: {
                            Text("Skip")
                                .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, isCompact ? 12 : 14)
                                .padding(.vertical, isCompact ? 6 : 8)
                                .liquidGlass(in: Capsule(), stroke: true, style: .clear)
                        }
                        .accessibilityLabel("Skip this question")
                    }
                }
            }
            .padding(.horizontal, QuizDesign.Layout.horizontalPadding)
            .padding(.vertical, isCompact ? QuizDesign.Spacing.sm : QuizDesign.Spacing.md)
            .background(.thinMaterial)
        }
    }
    
    @ViewBuilder
    private func inlineFeedbackBanner(viewModel: QuizViewModel) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: isCompact ? 14 : 16))
                    .foregroundStyle(viewModel.isCorrect ? .green : .red)
                    .symbolEffect(.bounce, value: viewModel.showFeedback)
                
                Text(viewModel.isCorrect ? "Correct!" : viewModel.correctName)
                    .font(.system(size: isCompact ? 14 : 16, weight: .bold, design: .rounded))
                    .foregroundStyle(viewModel.isCorrect ? .green : .red)
                    .lineLimit(1)
                
                Spacer()
            }
            if viewModel.hintLevel >= 3 {
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                    Text("Answer revealed")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, isCompact ? 12 : 14)
        .padding(.vertical, isCompact ? 8 : 10)
        .background((viewModel.isCorrect ? Color.green : Color.red).opacity(0.08), in: RoundedRectangle(cornerRadius: isCompact ? 8 : 10, style: .continuous))
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: isCompact ? 8 : 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: isCompact ? 8 : 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 8 : 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            (viewModel.isCorrect ? Color.green : Color.red).opacity(0.4),
                            (viewModel.isCorrect ? Color.green : Color.red).opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.isCorrect ? "Correct" : "Incorrect. Answer: \(viewModel.correctName)")
    }
    
    @ViewBuilder
    private func hintSection(viewModel: QuizViewModel, compact: Bool = false) -> some View {
        if compact {
            HStack(spacing: 10) {
                if viewModel.hintLevel > 0 {
                    HintDisplay(text: viewModel.hintText, compact: true)
                        .frame(maxWidth: .infinity)
                }
                HintButton(level: viewModel.hintLevel, compact: true, action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        viewModel.requestHint()
                    }
                })
            }
            .padding(.horizontal, 0)
        } else {
            VStack(spacing: 10) {
                if viewModel.hintLevel > 0 {
                    HintDisplay(text: viewModel.hintText, compact: false)
                }
                HintButton(level: viewModel.hintLevel, compact: false, action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        viewModel.requestHint()
                    }
                })
            }
            .padding(.horizontal, 0)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: QuizDesign.Spacing.section(compact: isCompact)) {
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: isCompact ? 56 : 72, weight: .light))
                .foregroundStyle(.tertiary)
            
            VStack(spacing: QuizDesign.Spacing.sm) {
                Text("No One to Quiz Yet")
                    .font(QuizDesign.Typography.title(compact: isCompact))
                    .multilineTextAlignment(.center)
                
                Text("Add contacts with photos to start practicing. The more faces you add, the better you'll remember.")
                    .font(QuizDesign.Typography.body(compact: isCompact))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                performExit()
            } label: {
                Text("Done")
                    .font(QuizDesign.Typography.bodySemibold(compact: false))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, QuizDesign.Spacing.md)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: QuizDesign.Layout.cornerRadius, style: .continuous))
            }
            .buttonStyle(QuizPrimaryButtonStyle())
            .padding(.horizontal, QuizDesign.Spacing.xxl)
            .padding(.top, QuizDesign.Spacing.md)
            .accessibilityLabel("Done, return to contacts")
        }
        .padding(QuizDesign.Spacing.xxl)
    }
    
    private var cardTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        } else {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        }
    }
    
    private func groupLabel(for contact: Contact) -> String {
        let names = (contact.tags ?? []).compactMap { $0.name }.filter { !$0.isEmpty }
        if names.isEmpty { return "—" }
        return names.sorted().joined(separator: ", ")
    }
    
    @ViewBuilder
    private func quizToolbarProgress(currentIndex: Int, total: Int, compact: Bool = false) -> some View {
        let progress = total > 0 ? Double(currentIndex) / Double(total) : 0.0
        let barWidth: CGFloat = compact ? 60 : 80
        let barHeight: CGFloat = compact ? 2 : 3
        VStack(spacing: compact ? 2 : 4) {
            Text("\(min(currentIndex + 1, total)) / \(total)")
                .font(.system(size: compact ? 11 : 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: barHeight)
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: max(0, g.size.width * progress), height: barHeight)
                }
            }
            .frame(width: barWidth, height: barHeight)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous), stroke: true, style: .clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Question \(currentIndex + 1) of \(total)")
    }
    
    private func setupViewModel() {
        let vm = QuizViewModel(modelContext: modelContext)
        
        if vm.hasSavedSession() {
            // Silently resume in‑progress quiz sessions without showing an alert
            _ = vm.resumeSession()
            viewModel = vm
        } else {
            vm.setupQuiz(with: contacts)
            viewModel = vm
        }
        // Keyboard is kept up by QuizInputBarRepresentable (UIKit first responder)
    }
    
    private func performExit() {
        // Save progress before exiting
        if let viewModel, viewModel.hasAnsweredAnyQuestion {
            viewModel.saveSessionState()
        }
        
        if let onRequestExit {
            let shouldExit = onRequestExit()
            if shouldExit {
                onComplete()
            }
        } else {
            onComplete()
        }
    }
}

private struct HintDisplay: View {
    let text: String
    var compact: Bool = false
    
    var body: some View {
        Text(text)
            .font(.system(size: compact ? 18 : 22, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .tracking(compact ? 3 : 4)
            .padding(.vertical, compact ? 10 : 12)
            .padding(.horizontal, compact ? 16 : 20)
            .frame(maxWidth: .infinity)
            .liquidGlass(in: RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous), stroke: true, style: .clear)
            .accessibilityLabel("Hint: \(text)")
    }
}

private struct HintButton: View {
    let level: Int
    var compact: Bool = false
    let action: () -> Void
    
    private var title: String {
        switch level {
        case 0: return "Hint"
        case 1, 2: return "More"
        default: return "Reveal"
        }
    }
    
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "lightbulb.fill")
                .font(.system(size: compact ? 13 : 14, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, compact ? 12 : 14)
                .padding(.vertical, compact ? 7 : 9)
                .background(Color.orange.opacity(0.12), in: Capsule())
                .background(.thinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.35), Color.orange.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        }
        .accessibilityLabel("Request \(title.lowercased())")
    }
}

private struct QuizPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(QuizDesign.Animation.microInteraction, value: configuration.isPressed)
    }
}

private struct ScoreDisplay: View {
    let score: Int
    let total: Int
    var compact: Bool = false
    
    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: compact ? 10 : 12))
                .foregroundStyle(.green)
            
            Text("\(score)/\(total)")
                .font(.system(size: compact ? 13 : 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Score: \(score) out of \(total)")
    }
}
