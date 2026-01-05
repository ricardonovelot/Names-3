import Foundation
import SwiftData

@Model
final class QuickNote {
    var uuid: UUID = UUID()
    var content: String = ""
    var date: Date = Date()
    var isLongAgo: Bool = false
    var isProcessed: Bool = false

    @Relationship(deleteRule: .nullify)
    var linkedContacts: [Contact]? = []
    
    @Relationship(deleteRule: .nullify)
    var linkedNotes: [Note]? = []

    init(uuid: UUID = UUID(), content: String = "", date: Date = Date(), isLongAgo: Bool = false, isProcessed: Bool = false, linkedContacts: [Contact]? = [], linkedNotes: [Note]? = []) {
        self.uuid = uuid
        self.content = content
        self.date = date
        self.isLongAgo = isLongAgo
        self.isProcessed = isProcessed
        self.linkedContacts = linkedContacts
        self.linkedNotes = linkedNotes
    }
}