//
//  FeedNextDayAlgorithm.swift
//  Names 3
//
//  First N days: recency biased (pick newest). After threshold: full random or exponential random.
//

import Foundation
import Photos

/// Context passed to the algorithm. All data is synchronously available.
struct FeedDaySelectionContext {
    struct DayInfo {
        let dayIndex: Int
        let dayStart: Date
        let start: Int
        let end: Int
        var videoCount: Int { end - start }
    }
    let dayInfos: [DayInfo]
    let exploredDayIndices: Set<Int>
    let lastAppendedDayIndex: Int?
    let fetchVideos: PHFetchResult<PHAsset>?
    let now: Date

    var exploredDaysCount: Int { exploredDayIndices.count }

    func candidates(resetIfExhausted: Bool = true) -> [DayInfo] {
        var cands = dayInfos.filter { !exploredDayIndices.contains($0.dayIndex) }
        if cands.isEmpty, resetIfExhausted {
            cands = dayInfos
            if let last = lastAppendedDayIndex, cands.count > 1 {
                cands.removeAll { $0.dayIndex == last }
            }
        }
        return cands
    }
}

enum FeedNextDayAlgorithm {
    /// First N days: recency biased. After threshold: full random or exponential random.
    static func pickNextDay(context: FeedDaySelectionContext) -> Int? {
        let cands = context.candidates()
        guard !cands.isEmpty else { return nil }

        let threshold = FeedExploreSettings.recentDaysThreshold
        let pastThreshold = context.exploredDaysCount >= threshold

        if !pastThreshold {
            // Recent phase: sample 6, pick newest
            let sampleCount = min(6, cands.count)
            let sample = (0..<sampleCount).compactMap { _ in cands.randomElement() }
            return sample.min(by: { $0.dayIndex < $1.dayIndex })?.dayIndex
        }

        // Past threshold: use explore mode
        switch FeedExploreSettings.exploreMode {
        case .recencyBiased:
            let sampleCount = min(6, cands.count)
            let sample = (0..<sampleCount).compactMap { _ in cands.randomElement() }
            return sample.min(by: { $0.dayIndex < $1.dayIndex })?.dayIndex

        case .fullRandom:
            return cands.randomElement()?.dayIndex

        case .exponentialRandom:
            return pickExponentialWeighted(candidates: cands)
        }
    }

    /// Weight by exp(-decay * dayIndex). dayIndex 0 = newest = highest weight.
    private static func pickExponentialWeighted(candidates: [FeedDaySelectionContext.DayInfo]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let decay = FeedExploreSettings.exponentialDecay

        var weights: [Double] = []
        for c in candidates {
            let w = exp(-decay * Double(c.dayIndex))
            weights.append(max(0.01, w))
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return candidates.randomElement()?.dayIndex }

        var r = Double.random(in: 0..<total)
        for (i, w) in weights.enumerated() {
            r -= w
            if r <= 0 { return candidates[i].dayIndex }
        }
        return candidates.last?.dayIndex
    }
}
