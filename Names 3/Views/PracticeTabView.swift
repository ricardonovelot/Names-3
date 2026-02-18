//
//  PracticeTabView.swift
//  Names 3
//
//  Inline Practice tab: quiz menu when idle, active quiz when in progress.
//

import SwiftUI
import SwiftData

struct PracticeTabView: View {
    let contacts: [Contact]
    let showQuizView: Bool
    let selectedQuizType: QuizType?
    let quizResetTrigger: UUID
    let onSelectQuiz: (QuizType) -> Void
    let onQuizComplete: () -> Void
    let onClose: () -> Void

    var body: some View {
        Group {
            if showQuizView, let quizType = selectedQuizType {
                quizContent(quizType)
            } else {
                QuizMenuView(
                    contacts: contacts,
                    onSelectQuiz: onSelectQuiz,
                    onDismiss: onClose,
                    isInline: true
                )
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showQuizView)
    }

    @ViewBuilder
    private func quizContent(_ quizType: QuizType) -> some View {
        if quizType == .notes {
            NotesQuizView(
                contacts: contacts,
                onDismiss: onQuizComplete
            )
        } else {
            QuizView(
                contacts: contacts,
                onComplete: onQuizComplete,
                onRequestExit: { true }
            )
            .id(quizResetTrigger)
        }
    }
}
