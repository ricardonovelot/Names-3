//
//  Item.swift
//  Names 3
//
//  Created by Ricardo on 14/10/24.
//

import Foundation
import SwiftData

@Model
class Contact {
    var name: String?
    var summary: String? = ""
    var isMetLongAgo: Bool = false
    var notes = [Note]()
    var tags = [Tag]()
    var timestamp: Date
    var photo: Data
    var group: String
    var cropOffsetX: Float
    var cropOffsetY: Float
    var cropScale: Float
    
    init(name: String = String(), summary: String = "", isMetLongAgo: Bool = false, timestamp: Date, notes: [Note], tags: [Tag] = [], photo: Data, group: String = "", cropOffsetX: Float = 0.0, cropOffsetY: Float = 0.0, cropScale: Float = 1.0) {
        self.name = name
        self.summary = summary
        self.isMetLongAgo = isMetLongAgo
        self.notes = notes
        self.tags = tags
        self.timestamp = timestamp
        self.photo = photo
        self.group = group
        self.cropOffsetX = cropOffsetX
        self.cropOffsetY = cropOffsetY
        self.cropScale = cropScale
    }
}

struct contactsGroup: Identifiable,Hashable {
    let id = UUID()
    let date: Date
    let contacts: [Contact]
    
    var title: String {
        let tags = contacts.flatMap { $0.tags.map { $0.name } }
        let uniqueTags = Set(tags) // Get unique tags
        if uniqueTags.isEmpty{
            return Date().description
        } else {
            return uniqueTags.joined(separator: ", ")
        }
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
    //@Attribute(.unique)
    var name: String
    
    init(name: String) {
        self.name = name
    }
}
