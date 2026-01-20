import TipKit
import SwiftUI

struct QuizStreakTip: Tip {
    static let quizCompleted = Event(id: "quiz-completed")
    
    var title: Text {
        Text("Build Your Memory Streak")
    }
    
    var message: Text? {
        Text("Take quizzes daily to strengthen your face recognition and build a streak")
    }
    
    var image: Image? {
        Image(systemName: "brain.head.profile")
    }
    
    var rules: [Rule] {
        [
            #Rule(Self.quizCompleted) {
                $0.donations.count > 0
            }
        ]
    }
}

struct NotesQuizTip: Tip {
    var title: Text {
        Text("Test Your Note Memory")
    }
    
    var message: Text? {
        Text("The Notes Quiz helps you recall important details about people")
    }
    
    var image: Image? {
        Image(systemName: "note.text")
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