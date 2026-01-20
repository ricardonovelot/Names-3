import TipKit
import SwiftUI

struct PhotoFaceNamingTip: Tip {
    var title: Text {
        Text("Swipe to Name Faces")
    }
    
    var message: Text? {
        Text("Swipe through detected faces and type a name to quickly assign them to contacts")
    }
    
    var image: Image? {
        Image(systemName: "person.crop.rectangle.stack")
    }
    
    var rules: [Rule] {
        [
            #Rule(TipEvents.faceAssigned) {
                $0.donations.count < 2
            }
        ]
    }
}

struct PhotoMultipleFacesTip: Tip {
    var title: Text {
        Text("Multiple Faces Detected")
    }
    
    var message: Text? {
        Text("We found multiple faces in this photo. Swipe through to name each person")
    }
    
    var image: Image? {
        Image(systemName: "person.3.fill")
    }
    
    var rules: [Rule] {
        [
            #Rule(TipEvents.multipleFacesDetected) {
                $0.donations.count >= 1
            }
        ]
    }
}

struct PhotoBulkImportTip: Tip {
    var title: Text {
        Text("Import from Photo Library")
    }
    
    var message: Text? {
        Text("Tap 'Bulk Add Faces' to scan your photo library and quickly name people")
    }
    
    var image: Image? {
        Image(systemName: "photo.stack")
    }
}

struct PhotoCommaSeparatedTip: Tip {
    var title: Text {
        Text("Name Multiple Faces at Once")
    }
    
    var message: Text? {
        Text("Type names separated by commas to assign them in order. Leave blanks to skip faces")
    }
    
    var image: Image? {
        Image(systemName: "comma.circle")
    }
}