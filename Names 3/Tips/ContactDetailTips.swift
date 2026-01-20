import TipKit
import SwiftUI

struct ContactNavigationTip: Tip {
    var title: Text {
        Text("Tap to View Details")
    }
    
    var message: Text? {
        Text("Tap any contact to see their full profile, add notes, or edit their information")
    }
    
    var image: Image? {
        Image(systemName: "hand.tap.fill")
    }
    
    var rules: [Rule] {
        [
            #Rule(TipEvents.contactCreated) {
                $0.donations.count >= 1
            },
            #Rule(TipEvents.contactViewed) {
                $0.donations.count == 0
            }
        ]
    }
}

struct ContactNoteTip: Tip {
    var title: Text {
        Text("Add Context with Notes")
    }
    
    var message: Text? {
        Text("Add notes to remember conversations, details, or anything important about this person")
    }
    
    var image: Image? {
        Image(systemName: "note.text.badge.plus")
    }
    
    var rules: [Rule] {
        [
            #Rule(TipEvents.noteAdded) {
                $0.donations.count < 3
            }
        ]
    }
}

struct ContactTagTip: Tip {
    var title: Text {
        Text("Organize with Tags")
    }
    
    var message: Text? {
        Text("Use tags to categorize contacts by context like #work, #family, or #conference")
    }
    
    var image: Image? {
        Image(systemName: "tag.fill")
    }
    
    var rules: [Rule] {
        [
            #Rule(TipEvents.tagAdded) {
                $0.donations.count < 2
            }
        ]
    }
}

struct ContactPhotoTip: Tip {
    var title: Text {
        Text("Add a Clear Face Photo")
    }
    
    var message: Text? {
        Text("Adding a clear, well-lit face photo helps with recognition and quiz accuracy")
    }
    
    var image: Image? {
        Image(systemName: "person.crop.circle.badge.plus")
    }
}