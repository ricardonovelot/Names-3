//
//  FeedScrollSmoothnessSettings.swift
//  Names 3
//
//  Defer until scroll end + prewarm: prewarm adjacent cells, defer heavy work until scroll ends.
//

import Foundation

struct FeedScrollSmoothnessSettings {
    static let maxContentCacheSize = 12

    /// A/B test: when true, uses improved scroll behavior (prefetch during scroll, ±2 prewarm, priority prefetch, video first-frame preheat).
    /// Toggle in Settings to compare smoothness.
    static let smoothScrollImprovementsKey = "Names3.FeedSmoothScrollImprovements"

    static var smoothScrollImprovements: Bool {
        get {
            if UserDefaults.standard.object(forKey: smoothScrollImprovementsKey) == nil {
                return true  // Default: improvements on
            }
            return UserDefaults.standard.bool(forKey: smoothScrollImprovementsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: smoothScrollImprovementsKey) }
    }
}
