//
//  NameFacesCarouselAssetFetcher.swift
//  Names 3
//
//  Fetches PHAssets by date for the Name Faces carousel sliding window.
//  Keeps PH/date logic out of WelcomeFaceNamingViewController and testable.
//

import Foundation
import Photos

/// Stateless fetcher for "assets older than date" and "assets newer than date"
/// for the Name Faces carousel. Runs work off the main thread.
enum NameFacesCarouselAssetFetcher {

    /// Fetches up to `limit` image and video assets with creationDate < date (newest-first).
    static func fetchAssetsOlderThan(_ date: Date?, limit: Int) async -> [PHAsset] {
        guard let date = date else { return [] }
        return await Task.detached(priority: .utility) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "creationDate < %@", date as NSDate)
            var part: [PHAsset] = []
            let imageResult = PHAsset.fetchAssets(with: .image, options: options)
            imageResult.enumerateObjects { asset, _, stop in
                part.append(asset)
                if part.count >= limit { stop.pointee = true }
            }
            var combined = part
            part = []
            let videoResult = PHAsset.fetchAssets(with: .video, options: options)
            videoResult.enumerateObjects { asset, _, stop in
                part.append(asset)
                if part.count >= limit { stop.pointee = true }
            }
            combined.append(contentsOf: part)
            let sorted = combined.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            return Array(sorted.prefix(limit))
        }.value
    }

    /// Fetches up to `limit` image and video assets with creationDate > date (newest-first).
    static func fetchAssetsNewerThan(_ date: Date?, limit: Int) async -> [PHAsset] {
        guard let date = date else { return [] }
        return await Task.detached(priority: .utility) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "creationDate > %@", date as NSDate)
            var part: [PHAsset] = []
            let imageResult = PHAsset.fetchAssets(with: .image, options: options)
            imageResult.enumerateObjects { asset, _, stop in
                part.append(asset)
                if part.count >= limit { stop.pointee = true }
            }
            var combined = part
            part = []
            let videoResult = PHAsset.fetchAssets(with: .video, options: options)
            videoResult.enumerateObjects { asset, _, stop in
                part.append(asset)
                if part.count >= limit { stop.pointee = true }
            }
            combined.append(contentsOf: part)
            let sorted = combined.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            return Array(sorted.prefix(limit))
        }.value
    }
}
