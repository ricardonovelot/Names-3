import TipKit
import SwiftUI

struct QuizStreakTip: Tip {
    private static let quizCompletedEvent = Tips.Event(id: "app.tips.quiz.completed")

    var title: Text {
        Text("Build Your Memory Streak")
    }

    var message: Text? {
        Text("Take quizzes daily to strengthen your face recognition and build a streak")
    }

    var image: Image? {
        Image(systemName: "rectangle.stack.fill")
    }

    var rules: [Rule] {
        [ #Rule(Self.quizCompletedEvent) { $0.donations.count > 0 } ]
    }
}

struct NotesQuizTip: Tip {
    var title: Text {
        Text("Rehearse Social Memories")
    }
    
    var message: Text? {
        Text("Gently strengthen your memory of what matters in people's lives")
    }
    
    var image: Image? {
        Image(systemName: "rectangle.stack.fill")
    }
}

struct QuickNotesProcessingTip: Tip {
    var title: Text {
        Text("Process Your Quick Notes")
    }
    
    var message: Text? {
        Text("Tap on quick notes to link them to contacts or expand them into full notes")
    }
    
    var image: Image? {
        Image(systemName: "arrow.right.circle")
    }
}