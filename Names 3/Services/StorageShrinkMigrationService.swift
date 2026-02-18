//
//  StorageShrinkMigrationService.swift
//  Names 3
//
//  One-time migration: downscale oversized Contact.photo and FaceEmbedding.thumbnailData
//  to reduce app storage. Runs in background so launch stays interactive.
//

import Foundation
import SwiftData
import UIKit
import os

enum StorageShrinkMigrationService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "StorageShrink")
    static let defaultsKey = "Names3.didShrinkStorage.v1"

    /// Threshold above which we consider Contact.photo oversized (bytes). ~80 KB = typical max for 640×640 @ 0.85.
    private static let contactPhotoShrinkThreshold = 80 * 1024

    /// Threshold above which we consider FaceEmbedding.thumbnailData oversized (bytes). ~40 KB = typical max for 320×320 @ 0.8.
    private static let faceThumbnailShrinkThreshold = 40 * 1024

    /// Returns true if the store has no data that could need shrinking.
    static func isStoreEmpty(context: ModelContext) -> Bool {
        do {
            let contactCount = try context.fetchCount(FetchDescriptor<Contact>())
            let embeddingCount = try context.fetchCount(FetchDescriptor<FaceEmbedding>())
            return contactCount == 0 && embeddingCount == 0
        } catch {
            logger.error("Failed to check store empty: \(error, privacy: .public)")
            return false
        }
    }

    /// Runs the migration. Call from the same thread/actor that owns the context.
    /// Returns (contactsShrunk, embeddingsShrunk).
    static func runMigration(context: ModelContext) -> (Int, Int) {
        var contactsShrunk = 0
        var embeddingsShrunk = 0

        do {
            let contacts = try context.fetch(FetchDescriptor<Contact>())
            for c in contacts {
                guard c.photo.count > contactPhotoShrinkThreshold else { continue }
                guard let image = UIImage(data: c.photo) else { continue }
                let shrunk = jpegDataForStoredContactPhoto(image)
                guard shrunk.count < c.photo.count else { continue }
                c.photo = shrunk
                contactsShrunk += 1
            }
            if contactsShrunk > 0 {
                try context.save()
                logger.info("Shrunk \(contactsShrunk) contact photo(s)")
            }
        } catch {
            logger.error("Failed to shrink contact photos: \(error, privacy: .public)")
        }

        do {
            let embeddings = try context.fetch(FetchDescriptor<FaceEmbedding>())
            for e in embeddings {
                guard e.thumbnailData.count > faceThumbnailShrinkThreshold else { continue }
                guard let image = UIImage(data: e.thumbnailData) else { continue }
                let shrunk = jpegDataForStoredFaceThumbnail(image)
                guard shrunk.count < e.thumbnailData.count else { continue }
                e.thumbnailData = shrunk
                embeddingsShrunk += 1
            }
            if embeddingsShrunk > 0 {
                try context.save()
                logger.info("Shrunk \(embeddingsShrunk) face embedding thumbnail(s)")
            }
        } catch {
            logger.error("Failed to shrink face thumbnails: \(error, privacy: .public)")
        }

        return (contactsShrunk, embeddingsShrunk)
    }
}
