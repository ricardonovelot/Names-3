import SwiftUI
import SwiftData

struct QuizView: View {
    let contacts: [Contact]
    let onComplete: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    
    @State private var viewModel: QuizViewModel?
    @State private var isTextFieldFocusedState: Bool = false
    @State private var showResumeDialog: Bool = false
    @State private var showExitConfirmation: Bool = false
    
    @Namespace private var animation
    
    var body: some View {
        Group {
            if let viewModel {
                quizContent(viewModel: viewModel)
            } else {
                Color.clear
                    .onAppear {
                        setupViewModel()
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    handleExitRequest()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .medium))
                        Text("Exit Quiz")
                            .font(.body.weight(.medium))
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .alert("Exit Quiz?", isPresented: $showExitConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Exit", role: .destructive) {
                onComplete()
            }
        } message: {
            Text("You can resume this quiz later from where you left off.")
        }
    }
    
    private func handleExitRequest() {
        guard let viewModel else {
            onComplete()
            return
        }
        
        if viewModel.hasAnsweredAnyQuestion {
            showExitConfirmation = true
        } else {
            viewModel.clearSession()
            onComplete()
        }
    }
    
    @ViewBuilder
    private func quizContent(viewModel: QuizViewModel) -> some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            
            if let item = viewModel.currentItem {
                ScrollView {
                    VStack(spacing: 20) {
                        QuizPhotoCard(contact: item.contact)
                            .padding(.top, 80)
                            .transition(cardTransition)
                            .id(item.id)
                        
                        if !(item.contact.tags?.isEmpty ?? true) {
                            groupSection(for: item.contact)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                        
                        inputSection(viewModel: viewModel)
                            .padding(.top, 8)
                        
                        if !viewModel.showFeedback {
                            hintSection(viewModel: viewModel)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        if viewModel.showFeedback {
                            feedbackSection(viewModel: viewModel)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                        
                        Spacer(minLength: 120)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    controlsBar(viewModel: viewModel)
                }
            } else {
                emptyStateView
            }
        }
        .overlay(alignment: .top) {
            if !viewModel.quizItems.isEmpty {
                QuizProgressBar(
                    currentIndex: viewModel.currentIndex,
                    totalQuestions: viewModel.quizItems.count
                )
                .padding(.top, 12)
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
                onMarkIncorrect: {
                    viewModel.markAsIncorrect()
                }
            )
        }
        .onChange(of: isTextFieldFocusedState) { _, newValue in
            viewModel.isTextFieldFocused = newValue
        }
        .onChange(of: viewModel.isTextFieldFocused) { _, newValue in
            isTextFieldFocusedState = newValue
        }
        .onShake {
            if !viewModel.showFeedback && viewModel.currentItem != nil {
                viewModel.requestHint()
            }
        }
        .overlay {
            if showResumeDialog {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .overlay {
                        QuizResumeDialog(
                            progress: "\(viewModel.currentIndex)/\(viewModel.quizItems.count) questions",
                            onResume: {
                                _ = viewModel.resumeSession()
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    isTextFieldFocusedState = true
                                }
                            },
                            onStartFresh: {
                                viewModel.clearSession()
                                viewModel.setupQuiz(with: contacts)
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    isTextFieldFocusedState = true
                                }
                            }
                        )
                    }
            }
        }
    }
    
    @ViewBuilder
    private func groupSection(for contact: Contact) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Group")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(groupLabel(for: contact))
                .font(.system(size: 17, weight: .semibold, design: .default))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Group: \(groupLabel(for: contact))")
    }
    
    @ViewBuilder
    private func inputSection(viewModel: QuizViewModel) -> some View {
        VStack(spacing: 16) {
            Text("Type their name")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            QuizTextField(
                text: Binding(
                    get: { viewModel.userInput },
                    set: { viewModel.userInput = $0 }
                ),
                isFocused: $isTextFieldFocusedState,
                placeholder: "Name",
                isDisabled: viewModel.showFeedback,
                onSubmit: {
                    guard !viewModel.showFeedback else { return }
                    viewModel.submitAnswer()
                }
            )
        }
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private func hintSection(viewModel: QuizViewModel) -> some View {
        VStack(spacing: 14) {
            if viewModel.hintLevel > 0 {
                HintDisplay(text: viewModel.hintText)
            }
            
            HStack(spacing: 12) {
                HintButton(
                    level: viewModel.hintLevel,
                    action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            viewModel.requestHint()
                        }
                    }
                )
                
                SkipButton {
                    viewModel.revealAndFail()
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    @ViewBuilder
    private func feedbackSection(viewModel: QuizViewModel) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.isCorrect ? .green : .red)
                    .symbolEffect(.bounce, value: viewModel.showFeedback)
                
                Text(viewModel.isCorrect ? "Correct!" : viewModel.correctName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(viewModel.isCorrect ? .green : .red)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(
                (viewModel.isCorrect ? Color.green : Color.red).opacity(0.12)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        (viewModel.isCorrect ? Color.green : Color.red).opacity(0.3),
                        lineWidth: 2
                    )
            )
            
            if viewModel.hintLevel >= 3 {
                Label("Answer revealed", systemImage: "eye.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.isCorrect ? "Correct answer" : "Incorrect. The answer is \(viewModel.correctName)")
    }
    
    @ViewBuilder
    private func controlsBar(viewModel: QuizViewModel) -> some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 16) {
                ScoreDisplay(
                    score: viewModel.score,
                    total: max(1, viewModel.currentIndex + 1)
                )
                
                Spacer()
                
                if !viewModel.showFeedback {
                    Button {
                        viewModel.skipQuestion()
                    } label: {
                        Text("Skip")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel("Skip this question")
                } else {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            viewModel.advance()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Next")
                            Image(systemName: "arrow.right")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 11)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                    }
                    .accessibilityLabel("Next question")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 70))
                .foregroundStyle(.tertiary)
            
            VStack(spacing: 10) {
                Text("No Contacts Available")
                    .font(.title2.bold())
                
                Text("Add some contacts to start the quiz")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
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
    
    private func setupViewModel() {
        let vm = QuizViewModel(modelContext: modelContext)
        
        if vm.hasSavedSession() {
            viewModel = vm
            showResumeDialog = true
        } else {
            vm.setupQuiz(with: contacts)
            viewModel = vm
            
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                isTextFieldFocusedState = true
            }
        }
    }
}

private struct HintDisplay: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 24, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .tracking(4)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel("Hint: \(text)")
    }
}

private struct HintButton: View {
    let level: Int
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
        }
        .accessibilityLabel("Request \(title.lowercased())")
    }
}

private struct SkipButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label("Skip", systemImage: "flag.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .accessibilityLabel("Skip and mark as wrong")
    }
}

private struct ScoreDisplay: View {
    let score: Int
    let total: Int
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
            
            Text("\(score)/\(total)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Score: \(score) out of \(total)")
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(ShakeGestureModifier(action: action))
    }
}

private struct ShakeGestureModifier: ViewModifier {
    let action: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
                action()
            }
    }
}

extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name(rawValue: "deviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}