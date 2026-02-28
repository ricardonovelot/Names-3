//
//  FeedPhotoGroupingMode.swift
//  Names 3
//
//  How photos are grouped into carousels in the feed.
//  Structure: video - carousel - video - carousel - ...
//  Only "Between Videos" is supported (other modes had scroll issues).
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

    /// Always returns .betweenVideo (only mode that works reliably with feed scrolling).
    static var current: FeedPhotoGroupingMode {
        get { .betweenVideo }
        set { _ = newValue }
    }
}
