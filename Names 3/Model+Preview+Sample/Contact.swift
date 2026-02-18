//
//  Item.swift
//  Names 3
//
//  Created by Ricardo on 14/10/24.
//

import Foundation
import SwiftData
import SwiftUI

@Model
class Contact {
    var uuid: UUID = UUID()
    var name: String? = ""
    var nicknames: [String]? = []
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
    
    @Relationship(inverse: \NoteRehearsalPerformance.contact)
    var noteRehearsalPerformance: NoteRehearsalPerformance?

    var timestamp: Date = Date()
    var photo: Data = Data()
    var group: String = ""
    var cropOffsetX: Float = 0.0
    var cropOffsetY: Float = 0.0
    var cropScale: Float = 1.0

    /// When true, photo gradient colors below are valid (computed when photo was set). Used for content-below-photo background.
    var hasPhotoGradient: Bool = false
    var photoGradientStartR: Float = 0
    var photoGradientStartG: Float = 0
    var photoGradientStartB: Float = 0
    var photoGradientEndR: Float = 0
    var photoGradientEndG: Float = 0
    var photoGradientEndB: Float = 0

    init(
        uuid: UUID = UUID(),
        name: String = "",
        nicknames: [String]? = [],
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
        quickNotes: [QuickNote]? = nil,
        quizPerformance: QuizPerformance? = nil,
        noteRehearsalPerformance: NoteRehearsalPerformance? = nil,
        hasPhotoGradient: Bool = false,
        photoGradientStartR: Float = 0,
        photoGradientStartG: Float = 0,
        photoGradientStartB: Float = 0,
        photoGradientEndR: Float = 0,
        photoGradientEndG: Float = 0,
        photoGradientEndB: Float = 0
    ) {
        self.uuid = uuid
        self.name = name
        self.nicknames = nicknames
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
        self.noteRehearsalPerformance = noteRehearsalPerformance
        self.hasPhotoGradient = hasPhotoGradient
        self.photoGradientStartR = photoGradientStartR
        self.photoGradientStartG = photoGradientStartG
        self.photoGradientStartB = photoGradientStartB
        self.photoGradientEndR = photoGradientEndR
        self.photoGradientEndG = photoGradientEndG
        self.photoGradientEndB = photoGradientEndB
    }
    
    var allAcceptableNames: [String] {
        var names: [String] = []
        
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            names.append(name)
        }
        
        if let nicknames = nicknames {
            names.append(contentsOf: nicknames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        }
        
        return Array(Set(names))
    }
    
    var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        
        if let firstNickname = nicknames?.first?.trimmingCharacters(in: .whitespacesAndNewlines), !firstNickname.isEmpty {
            return firstNickname
        }
        
        return "Unnamed"
    }

    /// Stored photo gradient for content-below-image background (nil when hasPhotoGradient is false).
    var photoGradientColors: (start: Color, end: Color)? {
        guard hasPhotoGradient else { return nil }
        let start = Color(
            red: Double(photoGradientStartR),
            green: Double(photoGradientStartG),
            blue: Double(photoGradientStartB)
        )
        let end = Color(
            red: Double(photoGradientEndR),
            green: Double(photoGradientEndG),
            blue: Double(photoGradientEndB)
        )
        return (start, end)
    }

    /// Tag names for display. Only safe when the store has not been invalidated (e.g. after CloudKit mirroring reset the context must be reset first).
    var tagNames: [String] {
        (tags ?? []).compactMap { $0.name }
    }
}

/// Snapshot of a contact’s group/date-related state before a move, used to restore on undo.
struct ContactMovementSnapshot: Hashable {
    let uuid: UUID
    let isMetLongAgo: Bool
    let timestamp: Date
    let tagNames: [String]
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
        let tagNames = contacts.flatMap(\.tagNames)
        let uniqueTags = Array(Set(tagNames)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if uniqueTags.isEmpty {
            return dateOnlyTitle
        } else {
            return uniqueTags.joined(separator: ", ")
        }
    }

    /// Title using only the date (no tag names). Use during CloudKit mirroring reset to avoid touching possibly invalidated Tag model references.
    var dateOnlyTitle: String {
        if isLongAgo {
            return NSLocalizedString("Met long ago", comment: "")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date)
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

    init(
        uuid: UUID = UUID(),
        content: String = "",
        creationDate: Date = Date(),
        isLongAgo: Bool = false,
        isArchived: Bool = false,
        archivedDate: Date? = nil,
        contact: Contact? = nil,
        quickNote: QuickNote? = nil
    ) {
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

    @MainActor
    static func fetchOrCreate(named name: String, in context: ModelContext, seedDate: Date) -> Tag? {
        guard let tag = fetchOrCreate(named: name, in: context) else { return nil }
        tag.updateRange(withSeed: seedDate)
        return tag
    }

    func updateRange(withSeed date: Date) {
        guard date != .distantPast && date <= Date() else { return }
        let (start, end) = Tag.defaultRange(for: date)
        if let rs = rangeStart {
            rangeStart = min(rs, start)
        } else {
            rangeStart = start
        }
        if let re = rangeEnd {
            rangeEnd = max(re, end)
        } else {
            rangeEnd = end
        }
    }

    static func defaultRange(for date: Date) -> (Date, Date) {
        let cal = Calendar.current
        let centerDay = cal.startOfDay(for: date)
        let start = cal.date(byAdding: .day, value: -3, to: centerDay) ?? centerDay
        let endStart = cal.date(byAdding: .day, value: 4, to: centerDay) ?? centerDay
        // end is exclusive upper bound like Photos predicates; keep as start of next day
        return (start, endStart)
    }
}