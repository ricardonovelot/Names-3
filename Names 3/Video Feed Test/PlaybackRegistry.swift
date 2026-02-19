import Foundation
import AVFoundation

@MainActor
final class PlaybackRegistry {
    static let shared = PlaybackRegistry()

    private let players = NSHashTable<AVPlayer>.weakObjects()

    func register(_ player: AVPlayer) {
        players.add(player)
    }

    func unregister(_ player: AVPlayer) {
        players.remove(player)
    }

    func willPlay(_ player: AVPlayer) {
        for p in players.allObjects where p !== player {
            p.pause()
        }
    }
}