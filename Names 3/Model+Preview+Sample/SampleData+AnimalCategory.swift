//
//  SampleData+AnimalCategory.swift
//  Names 3
//
//  Created by Ricardo on 15/10/24.
//

import Foundation
import SwiftData

extension Contact {
    static let ross = Contact(name: "Ross", summary: "He likes coffee", timestamp: Date(), notes: [], photo: Data())

    static func insertSampleData(modelContext: ModelContext) {
        // Add contacts to the model context.
        modelContext.insert(ross)
        
        // Add notes to the model context.
        // MARK: does a note need to be inserted in the model context ?
        modelContext.insert(Note.note_1)
        
        // Add tags to the model context.
        modelContext.insert(Tag.tag_1)
        modelContext.insert(Tag.tag_2)
        
        ross.notes.append(Note.note_1)
        
        // Set the category for each animal.
        // Animal.dog.category = mammal
    }
    
    static func reloadSampleData(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: Contact.self)
            insertSampleData(modelContext: modelContext)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}

extension Note {
    static let note_1 = Note(content: "Test Note 1", creationDate: Date())
}

extension Tag{
    static let tag_1 = Tag(name: "Coffee")
    static let tag_2 = Tag(name: "Department")
}
