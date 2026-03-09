//
//  FeedPositionStore.swift
//  Names 3
//
//  Persists the TikTok feed scroll position so the user returns to the same video when reopening the app.
//

import Foundation

enum FeedPositionStore {
    private static let key = "Names3.FeedPosition.AssetID"

    /// The asset ID of the currently visible feed item (video or first photo in carousel).
    static var savedAssetID: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let id = newValue {
                UserDefaults.standard.set(id, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    static func save(assetID: String) {
        savedAssetID = assetID
    }

    static func clear() {
        savedAssetID = nil
    }
}
