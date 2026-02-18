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
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
    }
    
    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
    }
    
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self
    )
    
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SchemaV2.self,
        toVersion: SchemaV3.self
    )
    
    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SchemaV3.self,
        toVersion: SchemaV4.self
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

enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Contact.self, Note.self, Tag.self, QuickNote.self, QuizPerformance.self]
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
        @Relationship(inverse: \QuizPerformance.contact)
        var quizPerformance: QuizPerformance?
        var timestamp: Date = Date()
        var photo: Data = Data()
        var group: String = ""
        var cropOffsetX: Float = 0.0
        var cropOffsetY: Float = 0.0
        var cropScale: Float = 1.0
        
        init(uuid: UUID = UUID(), name: String = "", summary: String = "", isMetLongAgo: Bool = false, isArchived: Bool = false, archivedDate: Date? = nil, timestamp: Date = Date(), notes: [Note]? = nil, tags: [Tag]? = nil, photo: Data = Data(), group: String = "", cropOffsetX: Float = 0.0, cropOffsetY: Float = 0.0, cropScale: Float = 1.0, quickNotes: [QuickNote]? = nil, quizPerformance: QuizPerformance? = nil) {
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
            self.quizPerformance = quizPerformance
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
        var rangeStart: Date? = nil
        var rangeEnd: Date? = nil
        @Relationship(inverse: \Contact.tags)
        var contacts: [Contact]? = []
        
        init(uuid: UUID = UUID(), name: String = "", isArchived: Bool = false, archivedDate: Date? = nil, contacts: [Contact]? = [], rangeStart: Date? = nil, rangeEnd: Date? = nil) {
            self.uuid = uuid
            self.name = name
            self.isArchived = isArchived
            self.archivedDate = archivedDate
            self.contacts = contacts
            self.rangeStart = rangeStart
            self.rangeEnd = rangeEnd
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
    
    @Model
    final class QuizPerformance {
        var uuid: UUID = UUID()
        var lastQuizzedDate: Date?
        var easeFactor: Float = 2.5
        var interval: Int = 0
        var repetitions: Int = 0
        var dueDate: Date = Date()
        var contact: Contact?
        
        init(uuid: UUID = UUID(), contact: Contact? = nil, lastQuizzedDate: Date? = nil, easeFactor: Float = 2.5, interval: Int = 0, repetitions: Int = 0, dueDate: Date = Date()) {
            self.uuid = uuid
            self.contact = contact
            self.lastQuizzedDate = lastQuizzedDate
            self.easeFactor = easeFactor
            self.interval = interval
            self.repetitions = repetitions
            self.dueDate = dueDate
        }
    }
}

// MARK: - Schema V4 (Contact photo gradient for content-below-image background)

enum SchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [Contact.self, Note.self, Tag.self, QuickNote.self, QuizPerformance.self]
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
        @Relationship(inverse: \QuizPerformance.contact)
        var quizPerformance: QuizPerformance?
        var timestamp: Date = Date()
        var photo: Data = Data()
        var group: String = ""
        var cropOffsetX: Float = 0.0
        var cropOffsetY: Float = 0.0
        var cropScale: Float = 1.0
        var hasPhotoGradient: Bool = false
        var photoGradientStartR: Float = 0
        var photoGradientStartG: Float = 0
        var photoGradientStartB: Float = 0
        var photoGradientEndR: Float = 0
        var photoGradientEndG: Float = 0
        var photoGradientEndB: Float = 0

        init(uuid: UUID = UUID(), name: String = "", summary: String = "", isMetLongAgo: Bool = false, isArchived: Bool = false, archivedDate: Date? = nil, timestamp: Date = Date(), notes: [Note]? = nil, tags: [Tag]? = nil, photo: Data = Data(), group: String = "", cropOffsetX: Float = 0.0, cropOffsetY: Float = 0.0, cropScale: Float = 1.0, quickNotes: [QuickNote]? = nil, quizPerformance: QuizPerformance? = nil, hasPhotoGradient: Bool = false, photoGradientStartR: Float = 0, photoGradientStartG: Float = 0, photoGradientStartB: Float = 0, photoGradientEndR: Float = 0, photoGradientEndG: Float = 0, photoGradientEndB: Float = 0) {
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
            self.quizPerformance = quizPerformance
            self.hasPhotoGradient = hasPhotoGradient
            self.photoGradientStartR = photoGradientStartR
            self.photoGradientStartG = photoGradientStartG
            self.photoGradientStartB = photoGradientStartB
            self.photoGradientEndR = photoGradientEndR
            self.photoGradientEndG = photoGradientEndG
            self.photoGradientEndB = photoGradientEndB
        }
    }
}