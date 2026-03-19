//
//  SavedCarouselMapping.swift
//  Names 3
//
//  Maps carousel signature (sorted asset IDs) to album localIdentifier for "is saved" checks.
//  Syncs via SwiftData + CloudKit.
//

import Foundation
import SwiftData

@Model
final class SavedCarouselMapping {
    var carouselSignature: String = ""
    var albumIdentifier: String = ""

    init(carouselSignature: String, albumIdentifier: String) {
        self.carouselSignature = carouselSignature
        self.albumIdentifier = albumIdentifier
    }
}
