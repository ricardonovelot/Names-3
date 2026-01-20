import SwiftUI
import SwiftData
import Combine

struct QuizView: View {
    let contacts: [Contact]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var quizItems: [QuizItem] = []
    @State private var currentIndex: Int = 0
    @State private var userInput: String = ""
    @State private var showFeedback: Bool = false
    @State private var isCorrect: Bool = false
    @State private var hintLevel: Int = 0
    @State private var score: Int = 0
    @State private var wrongAnswers: Int = 0
    @State private var showCompletionSheet: Bool = false
    @State private var skippedCount: Int = 0
    
    @FocusState private var isTextFieldFocused: Bool
    
    @State private var keyboardHeight: CGFloat = 0
    
    private struct QuizItem: Identifiable {
        let id = UUID()
        let contact: Contact
        let performance: QuizPerformance
    }
    
    private var currentItem: QuizItem? {
        guard currentIndex >= 0 && currentIndex < quizItems.count else { return nil }
        return quizItems[currentIndex]
    }
    
    private var correctName: String {
        currentItem?.contact.name ?? ""
    }
    
    private var hintText: String {
        guard hintLevel > 0, !correctName.isEmpty else { return "" }
        
        switch hintLevel {
        case 1:
            return String(correctName.prefix(1)) + String(repeating: "_", count: max(0, correctName.count - 1))
        case 2:
            let halfLength = correctName.count / 2
            return String(correctName.prefix(halfLength)) + String(repeating: "_", count: max(0, correctName.count - halfLength))
        default:
            return correctName
        }
    }
    
    private var shouldShowContextHints: Bool {
        guard let contact = currentItem?.contact else { return false }
        let hasPhoto = !contact.photo.isEmpty && UIImage(data: contact.photo) != nil
        let hasTags = !(contact.tags?.isEmpty ?? true)
        return !hasPhoto || !hasTags
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            if let item = currentItem {
                                photoSection(for: item.contact)
                                    .id("photo")
                                
                                groupSection(for: item.contact)
                                
                                inputSection
                                    .id("input")
                                
                                if keyboardHeight == 0 {
                                    hintSection
                                }
                                
                                feedbackSection
                            } else {
                                emptyStateSection
                            }
                            
                            Spacer(minLength: keyboardHeight > 0 ? keyboardHeight + 100 : 12)
                        }
                        .padding(.bottom, keyboardHeight > 0 ? 0 : 80)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: isTextFieldFocused) { oldValue, newValue in
                        if newValue {
                            withAnimation(.easeOut(duration: 0.3)) {
                                scrollProxy.scrollTo("input", anchor: .top)
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if keyboardHeight == 0 {
                    controlsOverlay
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCompletionSheet = true
                    } label: {
                        Text("End Quiz")
                            .font(.body)
                    }
                }
                ToolbarItem(placement: .principal) {
                    if !quizItems.isEmpty {
                        HStack(spacing: 4) {
                            Text("\(min(currentIndex + 1, quizItems.count))")
                                .font(.subheadline.weight(.semibold))
                            Text("of \(quizItems.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .onAppear {
                if quizItems.isEmpty {
                    setupQuiz()
                }
                setupKeyboardObservers()
                focusTextField()
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self)
            }
            .sheet(isPresented: $showCompletionSheet) {
                QuizCompletionView(
                    totalQuestions: quizItems.count,
                    correctAnswers: score,
                    wrongAnswers: wrongAnswers,
                    skippedCount: skippedCount,
                    isFullCompletion: currentIndex >= quizItems.count - 1,
                    onReview: {
                        showCompletionSheet = false
                        reviewSkippedQuestions()
                    },
                    onDismiss: {
                        dismiss()
                    }
                )
                .interactiveDismissDisabled()
            }
        }
    }
    
    @ViewBuilder
    private func contentSection(for contact: Contact) -> some View {
        VStack(spacing: 20) {
            photoSection(for: contact)
            
            contextSection(for: contact)
            
            inputSection
                .id("inputSection")
            
            hintSection
            
            feedbackSection
            
            controlsSection
            
            Spacer(minLength: 40)
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
    }
    
    @ViewBuilder
    private func photoSection(for contact: Contact) -> some View {
        ZStack {
            if let image = UIImage(data: contact.photo), image != UIImage() {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .black.opacity(0.0),
                                .black.opacity(0.15),
                                .black.opacity(0.35)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                ZStack {
                    RadialGradient(
                        colors: [
                            Color(uiColor: .secondarySystemBackground),
                            Color(uiColor: .tertiarySystemBackground)
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 140
                    )
                    
                    Image(systemName: "person.crop.square")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func contextSection(for contact: Contact) -> some View {
        VStack(spacing: 12) {
            if !(contact.tags?.isEmpty ?? true) {
                contextCard(
                    title: "Group",
                    content: groupLabel(for: contact),
                    icon: "person.2.fill"
                )
            }
            
            if shouldShowContextHints, let summary = contact.summary, !summary.isEmpty {
                contextCard(
                    title: "Context",
                    content: summary,
                    icon: "text.bubble.fill"
                )
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func contextCard(title: String, content: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
            }
            .foregroundStyle(.secondary)
            
            Text(content)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
        .padding(16)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), stroke: true)
    }
    
    @ViewBuilder
    private var inputSection: some View {
        VStack(spacing: 12) {
            Text("Type their name")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            HStack(spacing: 12) {
                TextField("Name", text: $userInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .autocapitalization(.words)
                    .disableAutocorrection(true)
                    .focused($isTextFieldFocused)
                    .disabled(showFeedback)
                    .onSubmit {
                        guard !showFeedback else { return }
                        submitAnswer()
                    }
                
                Button {
                    guard !showFeedback else { return }
                    submitAnswer()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(userInput.isEmpty ? .gray : .blue)
                }
                .disabled(showFeedback || userInput.isEmpty)
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var hintSection: some View {
        if !showFeedback {
            VStack(spacing: 12) {
                if hintLevel > 0 {
                    Text(hintText)
                        .font(.title2.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), stroke: true)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            hintLevel += 1
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                            Text(hintLevel == 0 ? "Hint" : (hintLevel < 3 ? "More" : "Reveal"))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .liquidGlass(in: Capsule(), stroke: true)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        revealAndFail()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "flag.fill")
                            Text("Skip")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .liquidGlass(in: Capsule(), stroke: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var feedbackSection: some View {
        if showFeedback {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(isCorrect ? .green : .red)
                    Text(isCorrect ? "Correct!" : "Answer: \(correctName)")
                        .font(.headline)
                        .foregroundStyle(isCorrect ? .green : .red)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), stroke: true)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
                if hintLevel >= 3 {
                    Text("Used full reveal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var controlsSection: some View {
        HStack {
            Text("Score: \(score)/\(currentIndex + 1)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if !showFeedback {
                Button("Skip") {
                    skipQuestion()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Next") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }
    
    @ViewBuilder
    private var emptyStateSection: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "questionmark.circle")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("No Contacts Available")
                    .font(.title2.bold())
                
                Text("Add some contacts to start the quiz")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func setupQuiz() {
        let valid = contacts.filter { contact in
            guard let name = contact.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return false
            }
            
            // Filter out contacts with insufficient recognition cues
            let hasPhoto = !contact.photo.isEmpty && UIImage(data: contact.photo) != nil
            let hasSummary = !(contact.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let hasNotes = !(contact.notes?.isEmpty ?? true)
            
            // Need at least photo OR meaningful context (not just tags)
            return hasPhoto || hasSummary || hasNotes
        }
        
        var items: [QuizItem] = []
        for contact in valid {
            let performance = getOrCreatePerformance(for: contact)
            items.append(QuizItem(contact: contact, performance: performance))
        }
        
        items.sort { item1, item2 in
            item1.performance.dueDate < item2.performance.dueDate
        }
        
        // Limit to 10 items per session (optimal learning batch size)
        let sessionSize = min(10, items.count)
        quizItems = Array(items.prefix(sessionSize))
    }
    
    private func getOrCreatePerformance(for contact: Contact) -> QuizPerformance {
        if let existing = contact.quizPerformance {
            return existing
        }
        
        let performance = QuizPerformance(contact: contact)
        modelContext.insert(performance)
        contact.quizPerformance = performance
        
        do {
            try modelContext.save()
        } catch {
            print("❌ [QuizView] Failed to create performance: \(error)")
        }
        
        return performance
    }
    
    private func submitAnswer() {
        guard let item = currentItem else { return }
        
        // Dismiss keyboard
        isTextFieldFocused = false
        
        let correct = isAnswerCorrect(userAnswer: userInput, correctName: correctName)
        isCorrect = correct
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showFeedback = true
        }
        
        if correct && hintLevel < 3 {
            score += 1
            let quality = calculateQuality()
            item.performance.recordSuccess(quality: quality)
            
            // Auto-advance on correct answer after brief celebration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.advance()
            }
        } else {
            wrongAnswers += 1
            item.performance.recordFailure()
            // Manual advance on wrong answer (user needs time to process)
        }
        
        do {
            try modelContext.save()
        } catch {
            print("❌ [QuizView] Failed to save performance: \(error)")
        }
    }
    
    private func revealAndFail() {
        // Dismiss keyboard
        isTextFieldFocused = false
        
        hintLevel = 3
        isCorrect = false
        wrongAnswers += 1
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showFeedback = true
        }
        
        if let item = currentItem {
            item.performance.recordFailure()
            do {
                try modelContext.save()
            } catch {
                print("❌ [QuizView] Failed to save performance: \(error)")
            }
        }
    }
    
    private func calculateQuality() -> Int {
        switch hintLevel {
        case 0: return 5
        case 1: return 4
        case 2: return 3
        default: return 2
        }
    }
    
    private func isAnswerCorrect(userAnswer: String, correctName: String) -> Bool {
        let normalizedUser = userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCorrect = correctName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        guard !normalizedUser.isEmpty else { return false }
        
        if normalizedUser == normalizedCorrect {
            return true
        }
        
        let distance = levenshteinDistance(normalizedUser, normalizedCorrect)
        let threshold = max(1, normalizedCorrect.count / 4)
        return distance <= threshold
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2Array.count + 1), count: s1Array.count + 1)
        
        for i in 0...s1Array.count {
            matrix[i][0] = i
        }
        for j in 0...s2Array.count {
            matrix[0][j] = j
        }
        
        for i in 1...s1Array.count {
            for j in 1...s2Array.count {
                if s1Array[i-1] == s2Array[j-1] {
                    matrix[i][j] = matrix[i-1][j-1]
                } else {
                    matrix[i][j] = min(
                        matrix[i-1][j] + 1,
                        matrix[i][j-1] + 1,
                        matrix[i-1][j-1] + 1
                    )
                }
            }
        }
        
        return matrix[s1Array.count][s2Array.count]
    }
    
    private func advance() {
        guard !quizItems.isEmpty else {
            dismiss()
            return
        }
        
        if currentIndex >= quizItems.count - 1 {
            dismiss()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showFeedback = false
            }
            userInput = ""
            hintLevel = 0
            currentIndex += 1
            focusTextField()
        }
    }
    
    private func focusTextField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            isTextFieldFocused = true
        }
    }
    
    private func groupLabel(for contact: Contact) -> String {
        let names = (contact.tags ?? []).compactMap { $0.name }.filter { !$0.isEmpty }
        if names.isEmpty { return "—" }
        return names.sorted().joined(separator: ", ")
    }
    
    private func skipQuestion() {
        guard let item = currentItem else { return }
        
        skippedCount += 1
        
        item.performance.dueDate = Date().addingTimeInterval(3600)
        
        do {
            try modelContext.save()
        } catch {
            print("❌ [QuizView] Failed to save skip: \(error)")
        }
        
        advanceWithoutFeedback()
    }
    
    private func reviewSkippedQuestions() {
        let skippedItems = quizItems.filter { item in
            let hourAgo = Date().addingTimeInterval(-3600)
            return item.performance.dueDate > hourAgo && item.performance.dueDate < Date().addingTimeInterval(7200)
        }
        
        if !skippedItems.isEmpty {
            currentIndex = 0
            quizItems = skippedItems
            score = 0
            skippedCount = 0
            showFeedback = false
            userInput = ""
            hintLevel = 0
            focusTextField()
        }
    }
    
    @ViewBuilder
    private func groupSection(for contact: Contact) -> some View {
        if !(contact.tags?.isEmpty ?? true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Group")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(groupLabel(for: contact))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack {
                Text("Score: \(score)/\(max(1, currentIndex + 1))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                
                if !showFeedback {
                    Button {
                        skipQuestion()
                    } label: {
                        Text("Skip")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        advance()
                    } label: {
                        HStack {
                            Text("Next")
                            Image(systemName: "arrow.right")
                        }
                        .font(.body.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [self] notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }
            
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = keyboardFrame.height
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }
    
    private func advanceWithoutFeedback() {
        guard !quizItems.isEmpty else {
            showCompletionScreen()
            return
        }
        
        if currentIndex >= quizItems.count - 1 {
            showCompletionScreen()
        } else {
            userInput = ""
            hintLevel = 0
            currentIndex += 1
            focusTextField()
        }
    }
    
    private func showCompletionScreen() {
        showCompletionSheet = true
    }
}