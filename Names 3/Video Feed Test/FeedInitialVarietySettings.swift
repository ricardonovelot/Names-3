//
//  FeedInitialVarietySettings.swift
//  Names 3
//
//  Heuristics for initial feed variety (Original mode). A/B testable.
//  - uniform: Fixed cap per day. Simple, predictable.
//  - momentCluster: Videos <30s apart = same moment. Cap per moment to avoid retakes.
//  - richDay: Days with many distinct moments = interesting → allow more.
//

import Foundation
import Photos

enum FeedInitialVarietyMode: String, CaseIterable, Identifiable {
    case uniform = "Uniform cap"
    case momentCluster = "Moment clusters"
    case richDay = "Rich day"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .uniform:
            return "Fixed cap per day. Simple, predictable."
        case .momentCluster:
            return "Videos within 30s = same moment. Cap per moment to avoid retakes."
        case .richDay:
            return "Days with many distinct moments get more videos."
        }
    }
}

struct FeedInitialVarietySettings {
    static let modeKey = "Names3.FeedInitialVarietyMode"
    static let uniformMaxKey = "Names3.FeedInitialVarietyUniformMax"
    static let momentGapKey = "Names3.FeedInitialVarietyMomentGapSec"
    static let maxPerClusterKey = "Names3.FeedInitialVarietyMaxPerCluster"
    static let maxPerDayKey = "Names3.FeedInitialVarietyMaxPerDay"
    static let richDayClusterBonusKey = "Names3.FeedInitialVarietyRichDayClusterBonus"

    static var mode: FeedInitialVarietyMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey),
                  let m = FeedInitialVarietyMode(rawValue: raw) else { return .momentCluster }
            return m
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    /// Max videos per day when using uniform mode.
    static var uniformMaxPerDay: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: uniformMaxKey)
            return v > 0 ? v : 10
        }
        set { UserDefaults.standard.set(max(3, min(25, newValue)), forKey: uniformMaxKey) }
    }

    /// Gap (seconds) below which videos are considered same moment.
    static var momentGapSec: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: momentGapKey)
            return v > 0 ? v : 30
        }
        set { UserDefaults.standard.set(max(10, min(120, newValue)), forKey: momentGapKey) }
    }

    /// Max videos per moment cluster (to avoid 5 retakes of same shot).
    static var maxPerCluster: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: maxPerClusterKey)
            return v > 0 ? v : 2
        }
        set { UserDefaults.standard.set(max(1, min(5, newValue)), forKey: maxPerClusterKey) }
    }

    /// Max videos per day (cap for all modes).
    static var maxPerDay: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: maxPerDayKey)
            return v > 0 ? v : 12
        }
        set { UserDefaults.standard.set(max(5, min(25, newValue)), forKey: maxPerDayKey) }
    }

    /// For richDay: extra videos per cluster beyond base (clusterCount * 2 + bonus).
    static var richDayClusterBonus: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: richDayClusterBonusKey)
            return v >= 0 ? v : 8
        }
        set { UserDefaults.standard.set(max(0, min(15, newValue)), forKey: richDayClusterBonusKey) }
    }
}

// MARK: - Sampling logic

enum FeedInitialVarietySampler {
    /// Samples videos from a day's slice using the configured heuristic.
    static func sample(
        _ videos: [PHAsset],
        mode: FeedInitialVarietyMode,
        maxTotal: Int
    ) -> [PHAsset] {
        guard !videos.isEmpty, maxTotal > 0 else { return [] }
        let gap = TimeInterval(FeedInitialVarietySettings.momentGapSec)
        let maxPerDay = min(FeedInitialVarietySettings.maxPerDay, maxTotal)

        switch mode {
        case .uniform:
            return uniformSample(videos, maxPerDay: FeedInitialVarietySettings.uniformMaxPerDay, maxTotal: maxTotal)
        case .momentCluster:
            return momentClusterSample(videos, gapSec: gap, maxPerCluster: FeedInitialVarietySettings.maxPerCluster, maxPerDay: maxPerDay, maxTotal: maxTotal)
        case .richDay:
            return richDaySample(videos, gapSec: gap, maxPerCluster: FeedInitialVarietySettings.maxPerCluster, maxPerDay: maxPerDay, maxTotal: maxTotal)
        }
    }

    /// Fixed cap per day.
    private static func uniformSample(_ videos: [PHAsset], maxPerDay: Int, maxTotal: Int) -> [PHAsset] {
        let take = min(maxPerDay, maxTotal, videos.count)
        return Array(videos.prefix(take))
    }

    /// Group by creation time; gaps < threshold = same moment. Cap per cluster.
    private static func momentClusterSample(
        _ videos: [PHAsset],
        gapSec: TimeInterval,
        maxPerCluster: Int,
        maxPerDay: Int,
        maxTotal: Int
    ) -> [PHAsset] {
        let sorted = videos.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        let clusters = buildClusters(sorted, gapSec: gapSec)
        let cap = min(maxPerDay, maxTotal)
        var result: [PHAsset] = []
        for cluster in clusters {
            guard result.count < cap else { break }
            let take = min(maxPerCluster, cluster.count, cap - result.count)
            result.append(contentsOf: cluster.prefix(take))
        }
        return result
    }

    /// Rich day: many clusters = interesting day → allow more. Formula: min(clusterCount * 2 + bonus, maxPerDay).
    private static func richDaySample(
        _ videos: [PHAsset],
        gapSec: TimeInterval,
        maxPerCluster: Int,
        maxPerDay: Int,
        maxTotal: Int
    ) -> [PHAsset] {
        let sorted = videos.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
        let clusters = buildClusters(sorted, gapSec: gapSec)
        let bonus = FeedInitialVarietySettings.richDayClusterBonus
        let dayAllowance = min(clusters.count * 2 + bonus, maxPerDay, maxTotal)
        var result: [PHAsset] = []
        for cluster in clusters {
            guard result.count < dayAllowance else { break }
            let take = min(maxPerCluster, cluster.count, dayAllowance - result.count)
            result.append(contentsOf: cluster.prefix(take))
        }
        return result
    }

    /// Groups consecutive videos with gap < threshold into same cluster.
    private static func buildClusters(_ sorted: [PHAsset], gapSec: TimeInterval) -> [[PHAsset]] {
        guard !sorted.isEmpty else { return [] }
        var clusters: [[PHAsset]] = []
        var current: [PHAsset] = [sorted[0]]
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            guard let prevDate = prev.creationDate, let currDate = curr.creationDate else {
                current.append(curr)
                continue
            }
            if currDate.timeIntervalSince(prevDate) <= gapSec {
                current.append(curr)
            } else {
                clusters.append(current)
                current = [curr]
            }
        }
        clusters.append(current)
        return clusters
    }
}
