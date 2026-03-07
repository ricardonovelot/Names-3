//
//  FeedExploreSettings.swift
//  Names 3
//
//  After N recent days, how to pick the next day when loading more.
//  - recencyBiased: Always pick newest (current behavior).
//  - fullRandom: Uniform pick across all days.
//  - exponentialRandom: Recent days preferred, decay toward randomness.
//

import Foundation

enum FeedExploreMode: String, CaseIterable, Identifiable {
    case recencyBiased = "Recency biased"
    case fullRandom = "Full random"
    case exponentialRandom = "Exponential random"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .recencyBiased:
            return "Always prefer newest days."
        case .fullRandom:
            return "Uniform pick across all days."
        case .exponentialRandom:
            return "Recent preferred, decays toward random."
        }
    }
}

struct FeedExploreSettings {
    static let recentDaysThresholdKey = "Names3.FeedExploreRecentDaysThreshold"
    static let exploreModeKey = "Names3.FeedExploreMode"
    static let exponentialDecayKey = "Names3.FeedExploreExponentialDecay"

    /// After this many days explored, switch from recency-biased to explore mode.
    static var recentDaysThreshold: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: recentDaysThresholdKey)
            return v > 0 ? v : 9
        }
        set { UserDefaults.standard.set(max(1, min(30, newValue)), forKey: recentDaysThresholdKey) }
    }

    /// When past threshold: recencyBiased, fullRandom, or exponentialRandom.
    static var exploreMode: FeedExploreMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: exploreModeKey),
                  let m = FeedExploreMode(rawValue: raw) else { return .exponentialRandom }
            return m
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: exploreModeKey) }
    }

    /// For exponential: decay factor. Higher = faster decay toward random. 1–10, default 3.
    static var exponentialDecay: Double {
        get {
            let v = UserDefaults.standard.double(forKey: exponentialDecayKey)
            return v > 0 ? v : 3
        }
        set { UserDefaults.standard.set(max(0.5, min(15, newValue)), forKey: exponentialDecayKey) }
    }
}
