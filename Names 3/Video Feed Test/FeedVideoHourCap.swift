//
//  FeedVideoHourCap.swift
//  Names 3
//
//  Max 1 video per 1-hour window for Recency, Explore after Recent, and Exponential Random.
//  When multiple videos fall in the same hour, one is chosen randomly. O(n) single pass.
//

import Foundation
import Photos

enum FeedVideoHourCap {
    private static let hourSec: TimeInterval = 3600

    /// Caps videos to max 1 per 1-hour window. When multiple fall in same hour, picks one randomly.
    /// Preserves newest-first order. Applied before interleaving in all feed modes.
    static func capOnePerHour(_ videos: [PHAsset]) -> [PHAsset] {
        guard videos.count > 1 else { return videos }
        var buckets: [Int: [PHAsset]] = [:]
        buckets.reserveCapacity(min(videos.count, 24 * 365)) // avoid rehashing for typical feeds
        for v in videos {
            guard let d = v.creationDate else { continue }
            let bucket = Int(d.timeIntervalSince1970 / hourSec)
            buckets[bucket, default: []].append(v)
        }
        let result = buckets.values.map { $0.randomElement()! }
        let capped = result.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        if capped.count < videos.count {
            print("[FeedVideoHourCap] \(videos.count) → \(capped.count) videos (max 1 per hour)")
        }
        return capped
    }
}
