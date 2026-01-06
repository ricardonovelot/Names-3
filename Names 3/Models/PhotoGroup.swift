import Foundation
import Photos
import CoreLocation

// MARK: - Photo Group Model

struct PhotoGroup: Identifiable, Hashable {
    let id: String
    let assets: [PHAsset]
    let representativeAssets: [PHAsset]
    let date: Date
    let location: CLLocation?
    let locationName: String?
    
    static func makeID(date: Date, location: CLLocation?) -> String {
        let dayStart = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        if let loc = location {
            let lat = (loc.coordinate.latitude * 10).rounded() / 10.0
            let lon = (loc.coordinate.longitude * 10).rounded() / 10.0
            return "\(Int(dayStart))|\(lat),\(lon)"
        } else {
            return "\(Int(dayStart))|n/a"
        }
    }
    
    var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date)
    }
    
    var subtitle: String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "\(assets.count) photos • Today"
        } else if calendar.isDateInYesterday(date) {
            return "\(assets.count) photos • Yesterday"
        }
        
        let components = calendar.dateComponents([.year, .month, .day], from: date, to: now)
        
        if let year = components.year, year > 0 {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "yyyy"
            let yearString = formatter.string(from: date)
            let yearWord = year == 1 ? "year ago" : "years ago"
            return "\(assets.count) photos • \(yearString), \(year) \(yearWord)"
        } else if let month = components.month, month > 0 {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "MMMM"
            let monthString = formatter.string(from: date)
            let monthWord = month == 1 ? "month ago" : "months ago"
            return "\(assets.count) photos • \(monthString), \(month) \(monthWord)"
        } else if let day = components.day, day > 0 {
            if day < 7 {
                let formatter = DateFormatter()
                formatter.locale = Locale.current
                formatter.dateFormat = "EEEE"
                let dayString = formatter.string(from: date)
                return "\(assets.count) photos • \(dayString)"
            } else {
                let dayWord = day == 1 ? "day ago" : "days ago"
                return "\(assets.count) photos • \(day) \(dayWord)"
            }
        } else {
            return "\(assets.count) photos • Today"
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PhotoGroup, rhs: PhotoGroup) -> Bool {
        lhs.id == rhs.id
    }
}