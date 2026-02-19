//
//  NameFacesCarouselAssetFetcher.swift
//  Names 3
//
//  Fetches PHAssets by date for the Name Faces carousel sliding window.
//  Keeps PH/date logic out of WelcomeFaceNamingViewController and testable.
//

import Foundation
import Photos

/// Stateless fetcher for the Name Faces carousel. Runs work off the main thread.
enum NameFacesCarouselAssetFetcher {
    private static let archivedIDsKey = WelcomeFaceNamingViewController.archivedAssetIDsKey

    /// Fetches up to `limit` most recent images and videos (newest-first). Used for Carousel non-bridge open.
    static func fetchInitialAssets(limit: Int) async -> [PHAsset] {
        await Task.detached(priority: .userInitiated) {
            let archivedIDs = Set(UserDefaults.standard.stringArray(forKey: archivedIDsKey) ?? [])
            let sortByDate = [NSSortDescriptor(key: "creationDate", ascending: false)]
            var images: [PHAsset] = []
            let imageOpts = PHFetchOptions()
            imageOpts.sortDescriptors = sortByDate
            PHAsset.fetchAssets(with: .image, options: imageOpts).enumerateObjects { asset, _, stop in
                if archivedIDs.contains(asset.localIdentifier) { return }
                images.append(asset)
                if images.count >= limit { stop.pointee = true }
            }
            var videos: [PHAsset] = []
            let videoOpts = PHFetchOptions()
            videoOpts.sortDescriptors = sortByDate
            PHAsset.fetchAssets(with: .video, options: videoOpts).enumerateObjects { asset, _, stop in
                if archivedIDs.contains(asset.localIdentifier) { return }
                videos.append(asset)
                if videos.count >= limit { stop.pointee = true }
            }
            let combined = images + videos
            let sorted = combined.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            return Array(sorted.prefix(limit))
        }.value
    }

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

    /// Fetches mixed photos and videos in a date range (for Feed↔Carousel bridge).
    /// Includes all videos (no duration filter) and photos. Ensures targetAsset is in the result.
    /// Returns sorted by creationDate descending, with the target asset's index.
    static func fetchMixedAssetsAround(
        targetAsset: PHAsset,
        rangeDays: Int = 14,
        limit: Int = 80
    ) async -> (assets: [PHAsset], targetIndex: Int) {
        guard let targetDate = targetAsset.creationDate else {
            return ([], 0)
        }
        let tol: TimeInterval = Double(rangeDays) * 24 * 60 * 60
        let lower = targetDate.addingTimeInterval(-tol)
        let upper = targetDate.addingTimeInterval(tol)
        let archivedIDs = Set(UserDefaults.standard.stringArray(forKey: archivedIDsKey) ?? [])
        let targetID = targetAsset.localIdentifier

        return await Task.detached(priority: .userInitiated) {
            var assets: [PHAsset] = []
            let opts = PHFetchOptions()
            opts.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate <= %@",
                lower as NSDate, upper as NSDate
            )
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let imageResult = PHAsset.fetchAssets(with: .image, options: opts)
            imageResult.enumerateObjects { asset, _, stop in
                if archivedIDs.contains(asset.localIdentifier) { return }
                if asset.mediaSubtypes.contains(.photoScreenshot) { return }
                assets.append(asset)
                if assets.count >= limit { stop.pointee = true }
            }
            let imgCount = assets.count
            let videoOpts = PHFetchOptions()
            videoOpts.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
                PHAssetMediaType.video.rawValue, lower as NSDate, upper as NSDate
            )
            videoOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let videoResult = PHAsset.fetchAssets(with: .video, options: videoOpts)
            var vAssets: [PHAsset] = []
            videoResult.enumerateObjects { asset, _, stop in
                if archivedIDs.contains(asset.localIdentifier) { return }
                vAssets.append(asset)
                if vAssets.count >= limit { stop.pointee = true }
            }
            var combined = assets + vAssets
            combined.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            combined = Array(combined.prefix(limit))

            var targetIndex = combined.firstIndex { $0.localIdentifier == targetID }
            if targetIndex == nil, targetAsset.mediaType == .image {
                combined.insert(targetAsset, at: 0)
                combined.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
                targetIndex = combined.firstIndex { $0.localIdentifier == targetID }
            } else if targetIndex == nil, targetAsset.mediaType == .video {
                combined.append(targetAsset)
                combined.sort { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
                targetIndex = combined.firstIndex { $0.localIdentifier == targetID }
            }
            return (combined, targetIndex ?? 0)
        }.value
    }
}
