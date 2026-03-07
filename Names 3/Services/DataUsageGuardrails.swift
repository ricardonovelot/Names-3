//
//  DataUsageGuardrails.swift
//  Names 3
//
//  User preferences for cellular and storage guardrails.
//

import Foundation

enum DataUsageGuardrails {
    static let allowsCellularForFeedKey = "Names3.AllowsCellularForFeedMedia"

    /// When true, allow loading feed media (videos, photos) over cellular. When false, only Wi‑Fi.
    static var allowsCellularForFeedMedia: Bool {
        get {
            if UserDefaults.standard.object(forKey: allowsCellularForFeedKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: allowsCellularForFeedKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: allowsCellularForFeedKey) }
    }

    /// Call from feed media loaders. Returns true when network (including cellular) may be used.
    static func shouldAllowNetworkForFeedMedia() -> Bool {
        if !ConnectivityMonitor.cachedUsesCellular { return true }
        return allowsCellularForFeedMedia
    }
}
