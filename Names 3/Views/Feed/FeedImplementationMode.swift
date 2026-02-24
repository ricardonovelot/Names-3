//
//  FeedImplementationMode.swift
//  Names 3
//
//  Five TikTok-style feed implementations for A/B testing stability and load.
//  Switch via Settings or UserDefaults for runtime comparison.
//

import Foundation

enum FeedImplementationMode: String, CaseIterable, Identifiable {
    case baseline = "Baseline"
    case singleSharedLayer = "1: Single Shared Layer"
    case twoLayers = "2: Two Layers"
    case perCellPlayer = "3: Per-Cell Player"
    case playerLooper = "4: AVPlayerLooper"
    case strictUnbind = "5: Strict Unbind"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .baseline:
            return "Current: shared player + per-cell layers, ownPlayer for inactive"
        case .singleSharedLayer:
            return "One AVPlayerLayer reparented between cells. No multi-layer sharing."
        case .twoLayers:
            return "Preview layer (first frame) + playback layer. Never same player on two layers."
        case .perCellPlayer:
            return "Each cell owns its AVPlayer. No shared player."
        case .playerLooper:
            return "Shared player with AVPlayerLooper for seamless looping."
        case .strictUnbind:
            return "Current approach with strict nil-before-assign ordering."
        }
    }

    private static let userDefaultsKey = "Names3.FeedImplementationMode"

    static var current: FeedImplementationMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let mode = FeedImplementationMode(rawValue: raw) else {
                return .strictUnbind  // Safer default: strict nil-before-assign
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}
