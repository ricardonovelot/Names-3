import SwiftUI
import SwiftData

private struct IdentifiableQuizKind: Identifiable {
    let kind: QuizKind
    var id: String { kind.rawValue }
}

enum QuizType {
    case faces
    case notes
}

struct QuizMenuView: View {
    let contacts: [Contact]
    let onSelectQuiz: (QuizType) -> Void
    let onDismiss: () -> Void
    /// When true, used inline (e.g. in tab); close button only calls onDismiss, no sheet dismiss.
    var isInline: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var streakCelebrationItem: IdentifiableQuizKind?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        
                        quizOptionsSection
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if !isInline { dismiss() }
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: $streakCelebrationItem) { item in
                StreakCelebrationView(
                    kind: item.kind,
                    accentColor: item.kind == .faces ? .blue : .orange,
                    onDismiss: { streakCelebrationItem = nil }
                )
            }
            .onAppear {
                QuizReminderService.shared.ensureScheduledIfEnabledAndAuthorized()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.blue)
            
            Text("Choose Practice Mode")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            
            Text("Strengthen different types of memory")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Quiz Options Section
    private var quizOptionsSection: some View {
        let streakManager = QuizStreakManager.shared
        return VStack(spacing: 16) {
            quizOptionCard(
                icon: "person.fill",
                iconColor: .blue,
                title: "Face Quiz",
                description: "Practice recalling names from faces",
                subtitle: "Semantic memory",
                streakCount: streakManager.currentStreak(for: .faces),
                onTap: { onSelectQuiz(.faces) },
                onStreakTap: { streakCelebrationItem = IdentifiableQuizKind(kind: .faces) }
            )
            quizOptionCard(
                icon: "note.text",
                iconColor: .orange,
                title: "Memory Rehearsal",
                description: "Rehearse what matters in people's lives",
                subtitle: "Episodic & social memory",
                streakCount: streakManager.currentStreak(for: .notes),
                onTap: { onSelectQuiz(.notes) },
                onStreakTap: { streakCelebrationItem = IdentifiableQuizKind(kind: .notes) }
            )
        }
    }
    
    // MARK: - Quiz Option Card
    @ViewBuilder
    private func quizOptionCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        subtitle: String,
        streakCount: Int,
        onTap: @escaping () -> Void,
        onStreakTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                
                Spacer()
                
                if streakCount > 0 {
                    Button(action: onStreakTap) {
                        HStack(spacing: 4) {
                            Text("🔥")
                                .font(.caption)
                            Text("\(streakCount)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(iconColor)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(iconColor.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
