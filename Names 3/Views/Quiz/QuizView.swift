import SwiftUI
import SwiftData

struct QuizView: View {
    let contacts: [Contact]
    @Environment(\.dismiss) private var dismiss

    struct Question: Identifiable, Hashable {
        let id = UUID()
        let answer: Contact
        let options: [Contact]
    }

    @State private var questions: [Question] = []
    @State private var index: Int = 0
    @State private var selection: Contact?
    @State private var score: Int = 0

    @State private var advanceTask: Task<Void, Never>?
    private let autoAdvanceDelay: TimeInterval = 0.8

    private var currentQuestion: Question? {
        guard index >= 0 && index < questions.count else { return nil }
        return questions[index]
    }

    private var isSelectionCorrect: Bool {
        guard let q = currentQuestion, let selection else { return false }
        return selection.id == q.answer.id
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let q = currentQuestion {
                    ZStack {
                        if let image = UIImage(data: q.answer.photo), image != UIImage() {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 260)
                                .clipped()
                                .overlay {
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            .black.opacity(0.0),
                                            .black.opacity(0.15),
                                            .black.opacity(0.35)
                                        ]),
                                        startPoint: .top, endPoint: .bottom
                                    )
                                }
                        } else {
                            ZStack {
                                Color(UIColor.secondarySystemGroupedBackground)
                                Image(systemName: "person.crop.square")
                                    .font(.system(size: 72, weight: .light))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Group")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(groupLabel(for: q.answer))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)

                    Text("Choose the correct name")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                    VStack(spacing: 10) {
                        ForEach(q.options, id: \.id) { option in
                            Button {
                                guard selection == nil else { return }
                                selection = option
                                if option.id == q.answer.id {
                                    score += 1
                                }
                                scheduleAutoAdvance(capturedIndex: index)
                            } label: {
                                HStack {
                                    Text(option.name ?? "Unknown")
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                                .background(buttonBackground(for: option, in: q))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(selection != nil)
                            .accessibilityLabel(option.name ?? "Option")
                        }
                    }
                    .padding(.horizontal)

                    if selection != nil {
                        Text(isSelectionCorrect ? "Correct" : "Wrong")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelectionCorrect ? Color.green : Color.red)
                            .transition(.opacity)
                            .padding(.top, 4)
                            .accessibilityHint(isSelectionCorrect ? "Correct answer selected" : "Incorrect answer selected")
                    }

                    HStack {
                        Text("Score: \(score)/\(questions.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Skip") {
                            advanceTask?.cancel()
                            advance()
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentQuestion == nil)
                        .accessibilityLabel("Skip question")
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)
                } else {
                    VStack(spacing: 12) {
                        Text("Not enough contacts to start a quiz.")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Button("Close") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }

                Spacer(minLength: 12)
            }
            .navigationTitle("Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .principal) {
                    if questions.count > 0 {
                        Text("Question \(min(index + 1, questions.count)) of \(questions.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
            .background(Color(UIColor.systemGroupedBackground))
            .onAppear {
                if questions.isEmpty {
                    questions = buildQuestions(from: contacts)
                }
            }
        }
    }

    private func scheduleAutoAdvance(capturedIndex: Int) {
        advanceTask?.cancel()
        advanceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoAdvanceDelay * 1_000_000_000))
            if !Task.isCancelled, index == capturedIndex {
                advance()
            }
        }
    }

    private func groupLabel(for contact: Contact) -> String {
        let names = (contact.tags ?? []).compactMap { $0.name }.filter { !$0.isEmpty }
        if names.isEmpty { return "—" }
        return names.sorted().joined(separator: ", ")
    }

    private func advance() {
        guard !questions.isEmpty else { dismiss(); return }
        if index >= questions.count - 1 {
            dismiss()
        } else {
            index += 1
            selection = nil
        }
    }

    private func buttonBackground(for option: Contact, in q: Question) -> some ShapeStyle {
        guard let selection else {
            return AnyShapeStyle(Color(UIColor.secondarySystemGroupedBackground))
        }
        if option.id == q.answer.id {
            return AnyShapeStyle(Color.green.opacity(0.25))
        } else if option.id == selection.id {
            return AnyShapeStyle(Color.red.opacity(0.25))
        } else {
            return AnyShapeStyle(Color(UIColor.secondarySystemGroupedBackground))
        }
    }

    private func buildQuestions(from all: [Contact]) -> [Question] {
        let valid = all.filter { contact in
            if let name = contact.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return true
            }
            return false
        }
        guard !valid.isEmpty else { return [] }

        let withPhotos = valid.filter { !$0.photo.isEmpty }
        let answersPool = withPhotos.isEmpty ? valid.shuffled() : withPhotos.shuffled()

        var qs: [Question] = []
        for answer in answersPool {
            let distractorPool = valid.filter { $0.id != answer.id }
            let count = min(3, max(0, distractorPool.count))
            let distractors = Array(distractorPool.shuffled().prefix(count))
            var options = distractors + [answer]
            options = Array(Set(options.map { $0.id })).compactMap { id in
                (options.first { $0.id == id })
            }
            options.shuffle()
            qs.append(Question(answer: answer, options: options))
        }

        let filtered = qs.filter { $0.options.count >= min(4, max(2, valid.count)) }
        return filtered.isEmpty ? qs : filtered
    }
}
