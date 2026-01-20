import TipKit
import SwiftUI

struct QuickInputBulkAddTip: Tip {
    static let contactCreated = Event(id: "contact-created")
    
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
            #Rule(Self.contactCreated) {
                $0.donations.count >= 3
            }
        ]
    }
}

struct QuickInputModeSwitchTip: Tip {
    static let quickNoteCreated = Event(id: "quick-note-created")
    
    var title: Text {
        Text("Switch to Quick Notes")
    }
    
    var message: Text? {
        Text("Tap the note icon to switch between people mode and quick notes mode for capturing temporary thoughts")
    }
    
    var image: Image? {
        Image(systemName: "note.text")
    }
    
    var rules: [Rule] {
        [
            #Rule(Self.quickNoteCreated) {
                $0.donations.count < 2
            }
        ]
    }
}

struct QuickInputCameraTip: Tip {
    static let photoTaken = Event(id: "photo-taken")
    
    var title: Text {
        Text("Capture Faces with Camera")
    }
    
    var message: Text? {
        Text("Tap the camera icon to quickly capture a photo and assign it to a contact")
    }
    
    var image: Image? {
        Image(systemName: "camera.fill")
    }
    
    var rules: [Rule] {
        [
            #Rule(Self.photoTaken) {
                $0.donations.count < 1
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
}