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
    var name: String
    var summary: String? = ""
    var notes = [Note]()
    var timestamp: Date
    var photo: Data
    
    init(name: String, timestamp: Date, notes: [Note], photo: Data) {
        self.name = name
        self.notes = notes
        self.timestamp = timestamp
        self.photo = photo
    }
}

@Model
final class Note {
    var owner: Contact
    var content: String
    var creationDate: Date
    
    init( content: String, creationDate: Date, owner: Contact) {
        self.content = content
        self.creationDate = creationDate
        self.owner = owner
    }
}
