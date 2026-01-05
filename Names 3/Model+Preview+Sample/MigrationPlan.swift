//
//  MigrationPlan.swift
//  Names 3
//
//  Schema migration for adding UUID fields
//

import Foundation
import SwiftData

enum Names3SchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }
    
    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
    
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
}

// MARK: - Schema V1 (Original without UUID)

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Contact.self, Note.self, Tag.self, QuickNote.self]
    }
    
    @Model
    final class Contact {
        var name: String? = ""
        var summary: String? = ""
        var isMetLongAgo: Bool = false
        var isArchived: Bool = false
        var archivedDate: Date? = nil
        var notes: [Note]?
        var tags: [Tag]?
        @Relationship(inverse: \QuickNote.linkedContacts)
        var quickNotes: [QuickNote]? = []
        var timestamp: Date = Date()
        var photo: Data = Data()
        var group: String = ""
        var cropOffsetX: Float = 0.0
        var cropOffsetY: Float = 0.0
        var cropScale: Float = 1.0
        
        init(name: String = "", summary: String = "", isMetLongAgo: Bool = false, isArchived: Bool = false, archivedDate: Date? = nil, timestamp: Date = Date(), notes: [Note]? = nil, tags: [Tag]? = nil, photo: Data = Data(), group: String = "", cropOffsetX: Float = 0.0, cropOffsetY: Float = 0.0, cropScale: Float = 1.0, quickNotes: [QuickNote]? = nil) {
            self.name = name
            self.summary = summary
            self.isMetLongAgo = isMetLongAgo
            self.isArchived = isArchived
            self.archivedDate = archivedDate
            self.notes = notes
            self.tags = tags
            self.timestamp = timestamp
            self.photo = photo
            self.group = group
            self.cropOffsetX = cropOffsetX
            self.cropOffsetY = cropOffsetY
            self.cropScale = cropScale
            self.quickNotes = quickNotes
        }
    }
    
    @Model
    final class Note {
        var content: String = ""
        var creationDate: Date = Date()
        var isLongAgo: Bool = false
        var isArchived: Bool = false
        var archivedDate: Date? = nil
        @Relationship(inverse: \Contact.notes)
        var contact: Contact?
        @Relationship(inverse: \QuickNote.linkedNotes)
        var quickNote: QuickNote?
        
        init(content: String = "", creationDate: Date = Date(), isLongAgo: Bool = false, isArchived: Bool = false, archivedDate: Date? = nil, contact: Contact? = nil, quickNote: QuickNote? = nil) {
            self.content = content
            self.creationDate = creationDate
            self.isLongAgo = isLongAgo
            self.isArchived = isArchived
            self.archivedDate = archivedDate
            self.contact = contact
            self.quickNote = quickNote
        }
    }
    
    @Model
    final class Tag {
        var name: String = ""
        var isArchived: Bool = false
        var archivedDate: Date? = nil
        @Relationship(inverse: \Contact.tags)
        var contacts: [Contact]? = []
        
        init(name: String = "", isArchived: Bool = false, archivedDate: Date? = nil, contacts: [Contact]? = []) {
            self.name = name
            self.isArchived = isArchived
            self.archivedDate = archivedDate
            self.contacts = contacts
        }
    }
    
    @Model
    final class QuickNote {
        var content: String = ""
        var date: Date = Date()
        var isLongAgo: Bool = false
        var isProcessed: Bool = false
        @Relationship(deleteRule: .nullify)
        var linkedContacts: [Contact]? = []
        @Relationship(deleteRule: .nullify)
        var linkedNotes: [Note]? = []
        
        init(content: String = "", date: Date = Date(), isLongAgo: Bool = false, isProcessed: Bool = false, linkedContacts: [Contact]? = [], linkedNotes: [Note]? = []) {
            self.content = content
            self.date = date
            self.isLongAgo = isLongAgo
            self.isProcessed = isProcessed
            self.linkedContacts = linkedContacts
            self.linkedNotes = linkedNotes
        }
    }
}

// MARK: - Schema V2 (With UUID)

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Contact.self, Note.self, Tag.self, QuickNote.self]
    }
    
    @Model
    final class Contact {
        var uuid: UUID = UUID()
        var name: String? = ""
        var summary: String? = ""
        var isMetLongAgo: Bool = false
        var isArchived: Bool = false
        var archivedDate: Date? = nil
        var notes: [Note]?
        var tags: [Tag]?
        @Relationship(inverse: \QuickNote.linkedContacts)
        var quickNotes: [QuickNote]? = []
        var timestamp: Date = Date()
        var photo: Data = Data()
        var group: String = ""
        var cropOffsetX: Float = 0.0
        var cropOffsetY: Float = 0.0
        var cropScale: Float = 1.0
        
        init(uuid: UUID = UUID(), name: String = "", summary: String = "", isMetLongAgo: Bool = false, isArchived: Bool = false, archivedDate: Date? = nil, timestamp: Date = Date(), notes: [Note]? = nil, tags: [Tag]? = nil, photo: Data = Data(), group: String = "", cropOffsetX: Float = 0.0, cropOffsetY: Float = 0.0, cropScale: Float = 1.0, quickNotes: [QuickNote]? = nil) {
            self.uuid = uuid
            self.name = name
            self.summary = summary
            self.isMetLongAgo = isMetLongAgo
            self.isArchived = isArchived
            self.archivedDate = archivedDate
            self.notes = notes
            self.tags = tags
            self.timestamp = timestamp
            self.photo = photo
            self.group = group
            self.cropOffsetX = cropOffsetX
            self.cropOffsetY = cropOffsetY
            self.cropScale = cropScale
            self.quickNotes = quickNotes
        }
    }
    
    @Model
    final class Note {
        var uuid: UUID = UUID()
        var content: String = ""
        var creationDate: Date = Date()
        var isLongAgo: Bool = false
        var isArchived: Bool = false
        var archivedDate: Date? = nil
        @Relationship(inverse: \Contact.notes)
        var contact: Contact?
        @Relationship(inverse: \QuickNote.linkedNotes)
        var quickNote: QuickNote?
        
        init(uuid: UUID = UUID(), content: String = "", creationDate: Date = Date(), isLongAgo: Bool = false, isArchived: Bool = false, archivedDate: Date? = nil, contact: Contact? = nil, quickNote: QuickNote? = nil) {
            self.uuid = uuid
            self.content = content
            self.creationDate = creationDate
            self.isLongAgo = isLongAgo
            self.isArchived = isArchived
            self.archivedDate = archivedDate
            self.contact = contact
            self.quickNote = quickNote
        }
    }
    
    @Model
    final class Tag {
        var uuid: UUID = UUID()
        var name: String = ""
        var isArchived: Bool = false
        var archivedDate: Date? = nil
        @Relationship(inverse: \Contact.tags)
        var contacts: [Contact]? = []
        
        init(uuid: UUID = UUID(), name: String = "", isArchived: Bool = false, archivedDate: Date? = nil, contacts: [Contact]? = []) {
            self.uuid = uuid
            self.name = name
            self.isArchived = isArchived
            self.archivedDate = archivedDate
            self.contacts = contacts
        }
    }
    
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
}