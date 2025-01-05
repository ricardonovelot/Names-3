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
    // could it be that this creates a lot of computations right after starting the app (calculating groups but more importantly the titles and subtitles)?
    // one idea is to calculate title and subtitle when the group is displayed, how to do this ?
    
    let id = UUID()
    let date: Date
    let contacts: [Contact]
    let parsedContacts: [Contact]
    
    var title: String {
        let tags = contacts.flatMap { $0.tags.map { $0.name } }
        let uniqueTags = Set(tags) // Get unique tags
        if uniqueTags.isEmpty{
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "MMM dd"
            return formatter.string(from: date)
        } else {
            return uniqueTags.joined(separator: ", ")
        }
    }
    
    var subtitle: String {
        let calendar = Calendar.current
        let now = Date()

        
        let yearFromDate = calendar.dateComponents([.year], from: date)
        if yearFromDate.year == 1{
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
