import Foundation
import SwiftData

@Model
final class QuickNote {
    var content: String = ""
    var date: Date = Date()
    var isLongAgo: Bool = false
    var isProcessed: Bool = false

    var linkedContacts: [Contact]? = []
    var linkedNotes: [Note]? = []

    init(content: String = "", date: Date = Date(), isLongAgo: Bool = false, isProcessed: Bool = false) {
        self.content = content
        self.date = date
        self.isLongAgo = isLongAgo
        self.isProcessed = isProcessed
    }
}