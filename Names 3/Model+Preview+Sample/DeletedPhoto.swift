//
//  DeletedPhoto.swift
//  Names 3
//
//  Tracks photo library assets the user has "deleted" (hidden) so they appear
//  in the Deleted view for restore or permanent delete.
//

import Foundation
import SwiftData

@Model
final class DeletedPhoto {
    /// PHAsset.localIdentifier
    var assetLocalIdentifier: String = ""
    /// When the user hid/deleted the photo
    var deletedDate: Date = Date()

    init(assetLocalIdentifier: String, deletedDate: Date = Date()) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.deletedDate = deletedDate
    }
}
