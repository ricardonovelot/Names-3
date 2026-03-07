//
//  JournalEntry.swift
//  Names 3
//

import Foundation
import SwiftData

@Model
final class JournalEntry {
    var uuid: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var date: Date = Date()

    init(uuid: UUID = UUID(), title: String = "", content: String = "", date: Date = Date()) {
        self.uuid = uuid
        self.title = title
        self.content = content
        self.date = date
    }
}
