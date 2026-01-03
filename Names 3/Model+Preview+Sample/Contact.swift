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

    init(
        name: String = "",
        summary: String = "",
        isMetLongAgo: Bool = false,
        isArchived: Bool = false,
        archivedDate: Date? = nil,
        timestamp: Date = Date(),
        notes: [Note]? = nil,
        tags: [Tag]? = nil,
        photo: Data = Data(),
        group: String = "",
        cropOffsetX: Float = 0.0,
        cropOffsetY: Float = 0.0,
        cropScale: Float = 1.0,
        quickNotes: [QuickNote]? = nil
    ) {
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

struct contactsGroup: Identifiable, Hashable {
    var id: String {
        if isLongAgo { return "long-ago" }
        let day = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        return "day-\(day)"
    }
    let date: Date
    let contacts: [Contact]
    let parsedContacts: [Contact]
    let isLongAgo: Bool
    
    var title: String {
        if isLongAgo {
            return NSLocalizedString("Met long ago", comment: "")
        }
        let tags = contacts.flatMap { ($0.tags ?? []).compactMap { $0.name } }
        let uniqueTags = Set(tags)
        if uniqueTags.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "MMM dd"
            return formatter.string(from: date)
        } else {
            return uniqueTags.joined(separator: ", ")
        }
    }
    
    var subtitle: String {
        if isLongAgo {
            return ""
        }
        let calendar = Calendar.current
        let now = Date()
        
        let yearFromDate = calendar.dateComponents([.year], from: date)
        if yearFromDate.year == 1 {
            return ""
        }
        
        if calendar.isDateInToday(date) {
            return NSLocalizedString("Today", comment: "")
        } else if calendar.isDateInYesterday(date) {
            return NSLocalizedString("Yesterday", comment: "")
        }

        let components = calendar.dateComponents([.year, .month, .day], from: date, to: now)

        if let year = components.year, year > 0 {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "yyyy"
            let yearString = formatter.string(from: date)
            let yearWord = year == 1 ? NSLocalizedString("year ago", comment: "") : NSLocalizedString("years ago", comment: "")
            return "\(yearString), \(year) \(yearWord)"
        } else if let month = components.month, month > 0 {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "MMMM"
            let monthString = formatter.string(from: date)
            let monthWord = month == 1 ? NSLocalizedString("month ago", comment: "") : NSLocalizedString("months ago", comment: "")
            return "\(monthString), \(month) \(monthWord)"
        } else if let day = components.day, day > 0 {
            if day < 7 {
                let formatter = DateFormatter()
                formatter.locale = Locale.current
                formatter.dateFormat = "EEEE"
                let dayString = formatter.string(from: date)
                return "\(dayString)"
            } else {
                let dayWord = day == 1 ? NSLocalizedString("day ago", comment: "") : NSLocalizedString("days ago", comment: "")
                return "\(day) \(dayWord)"
            }
        } else {
            return NSLocalizedString("Today", comment: "")
        }
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

    init(
        content: String = "",
        creationDate: Date = Date(),
        isLongAgo: Bool = false,
        isArchived: Bool = false,
        archivedDate: Date? = nil,
        contact: Contact? = nil,
        quickNote: QuickNote? = nil
    ) {
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

// Uniquing helpers for Tag
extension Tag {
    static func normalizedKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    var normalizedKey: String {
        Self.normalizedKey(name)
    }
    
    @MainActor
    static func fetchAll(in context: ModelContext) -> [Tag] {
        (try? context.fetch(FetchDescriptor<Tag>())) ?? []
    }
    
    @MainActor
    static func find(named name: String, in context: ModelContext) -> Tag? {
        let key = normalizedKey(name)
        return fetchAll(in: context).first { $0.normalizedKey == key }
    }
    
    @MainActor
    static func fetchOrCreate(named name: String, in context: ModelContext) -> Tag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = find(named: trimmed, in: context) {
            if existing.isArchived {
                existing.isArchived = false
                existing.archivedDate = nil
            }
            return existing
        }
        let tag = Tag(name: trimmed)
        context.insert(tag)
        return tag
    }
}