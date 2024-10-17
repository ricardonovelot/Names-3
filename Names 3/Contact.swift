//
//  Item.swift
//  Names 3
//
//  Created by Ricardo on 14/10/24.
//

import Foundation
import SwiftData

@Model
final class Contact {
    var name: String?
    var summary: String? = ""
    var isMetLongAgo: Bool = false
    var notes = [Note]()
    var tags = [Tag]()
    var timestamp: Date
    var photo: Data
    
    init(name: String = "", summary: String = "", isMetLongAgo: Bool = false, timestamp: Date, notes: [Note], tags: [Tag] = [], photo: Data) {
        self.name = name
        self.summary = summary
        self.isMetLongAgo = isMetLongAgo
        self.notes = notes
        self.tags = tags
        self.timestamp = timestamp
        self.photo = photo
    }
}

@Model
final class Note {
    var content: String
    var creationDate: Date
    
    init( content: String, creationDate: Date) {
        self.content = content
        self.creationDate = creationDate
    }
}

@Model
final class Tag {
    var name: String
    
    init(name: String) {
        self.name = name
    }
}
