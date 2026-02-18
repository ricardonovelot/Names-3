import SwiftUI
import SwiftData
import UIKit

struct NotesQuizView: View {
    let contacts: [Contact]
    let onDismiss: (() -> Void)?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var environmentDismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var dismiss: () -> Void {
        onDismiss ?? { environmentDismiss() }
    }
    
    @State private var viewModel: NoteRehearsalViewModel?
    @State private var showCompletion: Bool = false
    @State private var hasRecordedNotesCompletion: Bool = false
    
    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if viewModel.rehearsalItems.isEmpty {
                        emptyStateView
                    } else if viewModel.isComplete || showCompletion {
                        completionView
                    } else {
                        rehearsalContent(viewModel: viewModel)
                    }
                } else {
                    Color.clear
                        .onAppear {
                            setupViewModel()
                        }
                }
            }
            .navigationTitle("Memory Rehearsal")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func setupViewModel() {
        let vm = NoteRehearsalViewModel(modelContext: modelContext)
        vm.setupRehearsal(with: contacts)
        viewModel = vm
    }
    
    @ViewBuilder
    private func rehearsalContent(viewModel: NoteRehearsalViewModel) -> some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            
            if let item = viewModel.currentItem {
                ScrollView {
                    VStack(spacing: 24) {
                        // Person Cue Section
                        personCueSection(contact: item.contact)
                            .padding(.top, 60)
                        
                        // Soft Recall Prompt
                        if !viewModel.showRecallPromptBool {
                            softRecallPrompt
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                        
                        // Notes Section
                        if viewModel.showRecallPromptBool {
                            notesSection(viewModel: viewModel, item: item)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            
                            // Show indicator if multiple notes
                            if item.notes.count > 1 {
                                Text("Note \(viewModel.currentNoteIndex + 1) of \(item.notes.count)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                            }
                        }
                        
                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, 20)
                }
                .safeAreaInset(edge: .bottom) {
                    controlsBar(viewModel: viewModel)
                }
            } else {
                emptyStateView
            }
        }
        .overlay(alignment: .top) {
            topBar
        }
    }
    
    // MARK: - Person Cue Section
    /// Handles contacts with or without photos gracefully (like ContactDetailsView).
    @ViewBuilder
    private func personCueSection(contact: Contact) -> some View {
        let hasPhoto = !contact.photo.isEmpty && UIImage(data: contact.photo) != nil
        
        if hasPhoto {
            personCueWithPhoto(contact: contact)
        } else {
            personCueWithoutPhoto(contact: contact)
        }
    }
    
    @ViewBuilder
    private func personCueWithPhoto(contact: Contact) -> some View {
        VStack(spacing: 16) {
            QuizPhotoCard(contact: contact)
                .frame(height: 240)
            
            Text(contact.displayName)
                .font(.title.bold())
                .foregroundStyle(.primary)
            
            if let lastNote = lastNote(for: contact) {
                Text("Last note: \(formatDate(lastNote.creationDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func personCueWithoutPhoto(contact: Contact) -> some View {
        VStack(spacing: 16) {
            // Same frame as photo card, placeholder only
            QuizPhotoCard(contact: contact)
                .frame(height: 240)
            
            Text(contact.displayName)
                .font(.title.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            
            if let lastNote = lastNote(for: contact) {
                Text("Last note: \(formatDate(lastNote.creationDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func lastNote(for contact: Contact) -> Note? {
        contact.notes?
            .filter { !$0.isArchived }
            .sorted(by: { $0.creationDate > $1.creationDate })
            .first
    }
    
    // MARK: - Soft Recall Prompt
    private var softRecallPrompt: some View {
        VStack(spacing: 20) {
            Text("What's been going on in their life lately?")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Text("Take a moment to remember what matters to them.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    viewModel?.showRecallPrompt()
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding(.vertical, 32)
    }
    
    // MARK: - Notes Section
    @ViewBuilder
    private func notesSection(viewModel: NoteRehearsalViewModel, item: NoteRehearsalViewModel.RehearsalItem) -> some View {
        VStack(spacing: 20) {
            if let currentNote = viewModel.currentNote {
                noteCard(note: currentNote, viewModel: viewModel)
            }
        }
    }
    
    @ViewBuilder
    private func noteCard(note: Note, viewModel: NoteRehearsalViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.isNoteRevealed(note) {
                // Fully revealed note
                revealedNoteView(note: note, viewModel: viewModel)
            } else {
                // Masked note - progressive reveal
                maskedNoteView(note: note, viewModel: viewModel)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    @ViewBuilder
    private func maskedNoteView(note: Note, viewModel: NoteRehearsalViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("He mentioned something about…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Masked text - show partial content
            let maskedText = maskText(note.content)
            Text(maskedText)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(4)
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.revealCurrentNote()
                }
            } label: {
                HStack {
                    Text("Reveal")
                        .font(.headline)
                    Image(systemName: "eye")
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
    
    @ViewBuilder
    private func revealedNoteView(note: Note, viewModel: NoteRehearsalViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(note.content)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(4)
            
            // Reflection reinforcement
            Text("Did this come back to you?")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            
            HStack(spacing: 12) {
                difficultyButton(
                    title: "Yes, instantly",
                    difficulty: 2,
                    color: .green,
                    viewModel: viewModel
                )
                
                difficultyButton(
                    title: "Kind of",
                    difficulty: 1,
                    color: .orange,
                    viewModel: viewModel
                )
                
                difficultyButton(
                    title: "Not at all",
                    difficulty: 0,
                    color: .red,
                    viewModel: viewModel
                )
            }
        }
    }
    
    @ViewBuilder
    private func difficultyButton(
        title: String,
        difficulty: Int,
        color: Color,
        viewModel: NoteRehearsalViewModel
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.recordDifficulty(difficulty: difficulty)
                
                // Small delay before advancing
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds
                    viewModel.advanceToNextNote()
                }
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(color.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
    
    // MARK: - Masking Helper
    private func maskText(_ text: String) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return String(repeating: "▢", count: 20) }
        
        // Show first 2-3 words, then mask the rest with partial reveals
        let showCount = min(3, words.count)
        var result = words.prefix(showCount).joined(separator: " ")
        
        if words.count > showCount {
            // Add masked portion - show some characters of next word, then mask
            let remainingWords = Array(words.dropFirst(showCount))
            if let firstRemaining = remainingWords.first, firstRemaining.count > 2 {
                let partial = String(firstRemaining.prefix(2))
                result += " \(partial)\(String(repeating: "▢", count: max(8, text.count / 5)))"
            } else {
                result += " \(String(repeating: "▢", count: max(10, text.count / 4)))"
            }
        }
        
        return result
    }
    
    // MARK: - Controls Bar
    @ViewBuilder
    private func controlsBar(viewModel: NoteRehearsalViewModel) -> some View {
        HStack(spacing: 16) {
            Button {
                withAnimation {
                    viewModel.skipCurrentContact()
                }
            } label: {
                Text("Skip")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Exit")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            
            Spacer()
            
            if let viewModel {
                Text("\(viewModel.currentIndex + 1) / \(viewModel.rehearsalItems.count)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
    
    // MARK: - Completion View
    private var completionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.green)
            
            Text("Session Complete")
                .font(.title.bold())
            
            Text("You've rehearsed memories for \(viewModel?.rehearsalItems.count ?? 0) people.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
        .onAppear {
            recordMemoryRehearsalCompletionIfNeeded()
        }
    }
    
    private func recordMemoryRehearsalCompletionIfNeeded() {
        guard !hasRecordedNotesCompletion, let viewModel, !viewModel.rehearsalItems.isEmpty else { return }
        let count = viewModel.rehearsalItems.count
        QuizStreakManager.shared.recordQuizCompletion(
            quizKind: .notes,
            score: count,
            totalQuestions: count,
            isFullCompletion: true
        )
        hasRecordedNotesCompletion = true
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.orange)
            Text("No Notes to Rehearse")
                .font(.title.bold())
            Text("Add notes about people to start rehearsing memories.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
