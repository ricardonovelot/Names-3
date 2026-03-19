//
//  FeedSettingsSnapshot.swift
//  Names 3
//
//  Logs a snapshot of feed-related settings to the console for debugging.
//  Use this to verify configuration when the hour cap or other behavior seems off.
//

import Foundation

enum FeedSettingsSnapshot {
    /// Prints current feed settings to console. Call when feed loads.
    static func log() {
        let arch = FeedArchitectureMode.current.rawValue
        let exploreMode = FeedExploreSettings.exploreMode.rawValue
        let recentThreshold = FeedExploreSettings.recentDaysThreshold
        let exponentialDecay = FeedExploreSettings.exponentialDecay
        let initialVariety = FeedInitialVarietySettings.mode.rawValue
        let uniformMax = FeedInitialVarietySettings.uniformMaxPerDay
        let momentGap = FeedInitialVarietySettings.momentGapSec
        let maxPerCluster = FeedInitialVarietySettings.maxPerCluster
        let maxPerDay = FeedInitialVarietySettings.maxPerDay
        let photoGrouping = FeedPhotoGroupingMode.current.rawValue

        let lines = [
            "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
            "📋 Feed Settings Snapshot",
            "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
            "  Architecture:        \(arch)",
            "  Explore mode:         \(exploreMode)",
            "  Recent days threshold: \(recentThreshold)",
            "  Exponential decay:   \(exponentialDecay)",
            "  Initial variety:     \(initialVariety)",
            "  Uniform max/day:     \(uniformMax)",
            "  Moment gap (sec):    \(momentGap)",
            "  Max per cluster:     \(maxPerCluster)",
            "  Max per day:         \(maxPerDay)",
            "  Photo grouping:     \(photoGrouping)",
            "  Hour cap:            ON (max 1 video per hour)",
            "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        ]
        let output = lines.joined(separator: "\n")
       // DiagnosticsConfig.verbosePrint(output)
        Diagnostics.log("FeedSettingsSnapshot: arch=\(arch) explore=\(exploreMode) variety=\(initialVariety)")
    }
}
