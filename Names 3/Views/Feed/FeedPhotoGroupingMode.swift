//
//  FeedPhotoGroupingMode.swift
//  Names 3
//
//  How photos are grouped into carousels in the feed.
//  Structure: video - carousel - video - carousel - ...
//

import Foundation

enum FeedPhotoGroupingMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case betweenVideo = "Between Videos"
    case byDay = "By Day"
    case byCount = "By Count"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .off:
            return "No photos in feed (videos only)"
        case .betweenVideo:
            return "video → carousel(all photos until next video) → video"
        case .byDay:
            return "Group photos by same day into carousels"
        case .byCount:
            return "Group photos in batches of 3–6 per carousel"
        }
    }

    private static let userDefaultsKey = "Names3.FeedPhotoGroupingMode"

    static var current: FeedPhotoGroupingMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let mode = FeedPhotoGroupingMode(rawValue: raw) else {
                return .off
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}
