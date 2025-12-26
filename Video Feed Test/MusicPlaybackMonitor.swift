import Foundation
import MediaPlayer
import Combine

@MainActor
final class MusicPlaybackMonitor: ObservableObject {
    static let shared = MusicPlaybackMonitor()

    @Published private(set) var isPlaying: Bool = false

    private var appPlayer: MPMusicPlayerController!
    private var sysPlayer: MPMusicPlayerController!
    private var tokens: [NSObjectProtocol] = []

    private init() {
        appPlayer = MPMusicPlayerController.applicationMusicPlayer
        sysPlayer = MPMusicPlayerController.systemMusicPlayer

        appPlayer.beginGeneratingPlaybackNotifications()
        sysPlayer.beginGeneratingPlaybackNotifications()

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .MPMusicPlayerControllerPlaybackStateDidChange,
            .MPMusicPlayerControllerNowPlayingItemDidChange
        ]

        for name in names {
            tokens.append(center.addObserver(forName: name, object: appPlayer, queue: .main) { [weak self] _ in
                self?.refresh()
            })
            tokens.append(center.addObserver(forName: name, object: sysPlayer, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }

        refresh()
    }

    deinit {
        let center = NotificationCenter.default
        for t in tokens { center.removeObserver(t) }
        tokens.removeAll()
        MPMusicPlayerController.applicationMusicPlayer.endGeneratingPlaybackNotifications()
        MPMusicPlayerController.systemMusicPlayer.endGeneratingPlaybackNotifications()
    }

    private func refresh() {
        let playing = (appPlayer.playbackState == .playing) || (sysPlayer.playbackState == .playing)
        if isPlaying != playing {
            isPlaying = playing
        }
    }
}