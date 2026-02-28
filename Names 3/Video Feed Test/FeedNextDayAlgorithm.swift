//
//  FeedNextDayAlgorithm.swift
//  Names 3
//
//  Eight high-quality algorithms for choosing the next day segment in Explore mode.
//  Each algorithm uses only data already available (dayRanges, fetchVideos) or easily obtainable (PHAsset properties).
//

import Foundation
import Photos

/// Context passed to each algorithm. All data is synchronously available.
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

    func daysSinceNow(_ dayStart: Date) -> Int {
        Calendar.current.dateComponents([.day], from: dayStart, to: now).day ?? 0
    }
}

enum FeedNextDayAlgorithm: String, CaseIterable, Identifiable {
    case recencyBiased = "Recency biased"
    case surprise = "Surprise"
    case favoritesFirst = "Favorites first"
    case durationSweetSpot = "Duration sweet spot"
    case richness = "Richness"
    case temporalVariety = "Temporal variety"
    case discovery = "Discovery"
    case quality = "Quality"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .recencyBiased:
            return "Sample 6 unseen days, pick newest. Best cache hit rate."
        case .surprise:
            return "Maximize unpredictability. Favors days far from recently shown."
        case .favoritesFirst:
            return "Prioritize days with more favorited videos."
        case .durationSweetSpot:
            return "Prefer days with avg video length 15–60s (TikTok-style)."
        case .richness:
            return "Prefer days with more videos. More content = more scroll."
        case .temporalVariety:
            return "Alternate recent ↔ old. Creates narrative arc."
        case .discovery:
            return "Favor days not seen recently. Time-weighted freshness."
        case .quality:
            return "Prefer high-res portrait videos, reasonable duration."
        }
    }

    private static let userDefaultsKey = "Names3.FeedNextDayAlgorithm"

    static var current: FeedNextDayAlgorithm {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let algo = FeedNextDayAlgorithm(rawValue: raw) else { return .recencyBiased }
            return algo
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey) }
    }

    func pickNextDay(context: FeedDaySelectionContext) -> Int? {
        switch self {
        case .recencyBiased: return recencyBiased(context)
        case .surprise: return surprise(context)
        case .favoritesFirst: return favoritesFirst(context)
        case .durationSweetSpot: return durationSweetSpot(context)
        case .richness: return richness(context)
        case .temporalVariety: return temporalVariety(context)
        case .discovery: return discovery(context)
        case .quality: return quality(context)
        }
    }

    // MARK: - 1. Recency biased (current default)
    private func recencyBiased(_ ctx: FeedDaySelectionContext) -> Int? {
        let cands = ctx.candidates()
        guard !cands.isEmpty else { return nil }
        let sampleCount = min(6, cands.count)
        let sample = (0..<sampleCount).compactMap { _ in cands.randomElement() }
        return sample.min(by: { $0.dayIndex < $1.dayIndex })?.dayIndex
    }

    // MARK: - 2. Surprise
    private func surprise(_ ctx: FeedDaySelectionContext) -> Int? {
        let cands = ctx.candidates()
        guard !cands.isEmpty else { return nil }
        let last = ctx.lastAppendedDayIndex
        let distances = cands.map { d -> (FeedDaySelectionContext.DayInfo, Int) in
            let dist = last.map { abs(d.dayIndex - $0) } ?? ctx.dayInfos.count
            return (d, dist)
        }
        let maxDist = max(1, distances.map { $0.1 }.max() ?? 1)
        let weighted = distances.map { d, dist in
            (d, dist + Int.random(in: 0..<maxDist))
        }
        return weighted.max(by: { $0.1 < $1.1 })?.0.dayIndex
    }

    // MARK: - 3. Favorites first
    private func favoritesFirst(_ ctx: FeedDaySelectionContext) -> Int? {
        guard let vResult = ctx.fetchVideos else { return recencyBiased(ctx) }
        let cands = ctx.candidates()
        guard !cands.isEmpty else { return nil }
        let scores = cands.map { info -> (FeedDaySelectionContext.DayInfo, Int) in
            var favCount = 0
            for i in info.start..<info.end {
                if vResult.object(at: i).isFavorite { favCount += 1 }
            }
            return (info, favCount)
        }
        let withRandomTieBreak = scores.map { info, score in
            (info, score * 100 + Int.random(in: 0..<100))
        }
        return withRandomTieBreak.max(by: { $0.1 < $1.1 })?.0.dayIndex
    }

    // MARK: - 4. Duration sweet spot (15–60s)
    private func durationSweetSpot(_ ctx: FeedDaySelectionContext) -> Int? {
        guard let vResult = ctx.fetchVideos else { return recencyBiased(ctx) }
        let cands = ctx.candidates()
        guard !cands.isEmpty else { return nil }
        let sweetMin: TimeInterval = 15
        let sweetMax: TimeInterval = 60
        let scores = cands.map { info -> (FeedDaySelectionContext.DayInfo, Double) in
            var total: TimeInterval = 0
            var count = 0
            for i in info.start..<info.end {
                let d = vResult.object(at: i).duration
                if d >= 1 { total += d; count += 1 }
            }
            let avg = count > 0 ? total / Double(count) : 0
            let distFromSweet = avg <= sweetMin ? sweetMin - avg
                : avg >= sweetMax ? avg - sweetMax
                : 0
            return (info, -distFromSweet)
        }
        return scores.max(by: { $0.1 < $1.1 })?.0.dayIndex
    }

    // MARK: - 5. Richness (more content)
    private func richness(_ ctx: FeedDaySelectionContext) -> Int? {
        let cands = ctx.candidates()
        guard !cands.isEmpty else { return nil }
        let scores = cands.map { info -> (FeedDaySelectionContext.DayInfo, Int) in
            (info, info.videoCount * 10 + Int.random(in: 0..<10))
        }
        return scores.max(by: { $0.1 < $1.1 })?.0.dayIndex
    }

    // MARK: - 6. Temporal variety (alternate recent ↔ old)
    private func temporalVariety(_ ctx: FeedDaySelectionContext) -> Int? {
        let cands = ctx.candidates()
        guard !cands.isEmpty else { return nil }
        guard let last = ctx.lastAppendedDayIndex,
              let lastInfo = ctx.dayInfos.first(where: { $0.dayIndex == last }) else {
            return recencyBiased(ctx)
        }
        let lastDaysAgo = ctx.daysSinceNow(lastInfo.dayStart)
        let isLastRecent = lastDaysAgo <= 30
        let preferred = cands.filter { info in
            let daysAgo = ctx.daysSinceNow(info.dayStart)
            return isLastRecent ? daysAgo > 30 : daysAgo <= 30
        }
        let pool = preferred.isEmpty ? cands : preferred
        return pool.randomElement()?.dayIndex
    }

    // MARK: - 7. Discovery (time since last shown)
    private func discovery(_ ctx: FeedDaySelectionContext) -> Int? {
        let cands = ctx.candidates(resetIfExhausted: false)
        guard !cands.isEmpty else { return ctx.candidates().randomElement()?.dayIndex }
        let scores = cands.map { info -> (FeedDaySelectionContext.DayInfo, Int) in
            let daysAgo = max(0, ctx.daysSinceNow(info.dayStart))
            return (info, daysAgo * 2 + Int.random(in: 0..<5))
        }
        return scores.max(by: { $0.1 < $1.1 })?.0.dayIndex
    }

    // MARK: - 8. Quality (resolution + portrait + duration)
    private func quality(_ ctx: FeedDaySelectionContext) -> Int? {
        guard let vResult = ctx.fetchVideos else { return recencyBiased(ctx) }
        let cands = ctx.candidates()
        guard !cands.isEmpty else { return nil }
        let scores = cands.map { info -> (FeedDaySelectionContext.DayInfo, Double) in
            var score: Double = 0
            for i in info.start..<info.end {
                let a = vResult.object(at: i)
                let pixels = Double(a.pixelWidth * a.pixelHeight)
                let isPortrait = a.pixelHeight >= a.pixelWidth
                let dur = a.duration
                score += min(1, pixels / 1_000_000)
                if isPortrait { score += 0.5 }
                if dur >= 5, dur <= 120 { score += 0.3 }
            }
            return (info, score + Double.random(in: 0..<0.1))
        }
        return scores.max(by: { $0.1 < $1.1 })?.0.dayIndex
    }
}
