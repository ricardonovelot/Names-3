import TipKit
import SwiftUI

struct QuickInputFormatTip: Tip {
    var title: Text {
        Text("Quick Add Your First Friend")
    }
    
    var message: Text? {
        Text("Type their name, add double colon (::), then what you remember about them. Add \"long time ago\" if you haven't seen them recently.")
    }
    
    var image: Image? {
        Image(systemName: "person.fill.questionmark")
    }
    
    var actions: [Action] {
        [
            Action(id: "try-example", title: "Try Example") {
                NotificationCenter.default.post(
                    name: .quickInputShowExample,
                    object: nil,
                    userInfo: ["example": "Sarah:: met at tech conference, long time ago"]
                )
            }
        ]
    }
    
    var rules: [Rule] {
        [
            #Rule(TipEvents.contactCreated) {
                $0.donations.count == 0
            }
        ]
    }
}

struct QuickInputBulkAddTip: Tip {
    var title: Text {
        Text("Add Multiple People at Once")
    }
    
    var message: Text? {
        Text("Type names separated by commas to quickly add multiple contacts. Example: \"Alice, Bob, Charlie\"")
    }
    
    var image: Image? {
        Image(systemName: "person.2.fill")
    }
    
    var rules: [Rule] {
        [
            #Rule(TipEvents.contactCreated) {
                $0.donations.count >= 3
            }
        ]
    }
}

struct QuickInputTagsTip: Tip {
    var title: Text {
        Text("Organize with Tags")
    }
    
    var message: Text? {
        Text("Add tags to contacts using #hashtags. Example: \"Alice #work #designer\"")
    }
    
    var image: Image? {
        Image(systemName: "number")
    }
    
    var rules: [Rule] {
        [
            #Rule(TipEvents.contactCreated) {
                $0.donations.count >= 5
            },
            #Rule(TipEvents.tagAdded) {
                $0.donations.count == 0
            }
        ]
    }
}

struct QuickInputDateParsingTip: Tip {
    var title: Text {
        Text("Add Dates Naturally")
    }
    
    var message: Text? {
        Text("Include dates like \"yesterday\", \"last week\", or \"June 15\" and they'll be automatically parsed")
    }
    
    var image: Image? {
        Image(systemName: "calendar")
    }
    
    var rules: [Rule] {
        [
            #Rule(TipEvents.contactCreated) {
                $0.donations.count >= 8
            }
        ]
    }
}

struct QuickInputQuizTip: Tip {
    var title: Text {
        Text("Test Your Memory")
    }
    
    var message: Text? {
        Text("Tap the quiz button to practice recognizing faces and build your memory")
    }
    
    var image: Image? {
        Image(systemName: "questionmark.circle.fill")
    }
}