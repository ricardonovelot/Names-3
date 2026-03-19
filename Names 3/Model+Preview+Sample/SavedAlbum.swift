//
//  SavedAlbum.swift
//  Names 3
//
//  Persists saved album/asset identifiers for the Albums tab. Syncs via SwiftData + CloudKit.
//

import Foundation
import SwiftData

@Model
final class SavedAlbum {
    /// Format: "album:localId" or "asset:localId". Legacy IDs without prefix are albums.
    var identifier: String = ""
    var sortOrder: Int = 0

    init(identifier: String, sortOrder: Int = 0) {
        self.identifier = identifier
        self.sortOrder = sortOrder
    }
}
