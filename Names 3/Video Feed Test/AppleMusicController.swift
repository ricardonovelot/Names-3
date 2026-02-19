import Foundation
import MediaPlayer

final class AppleMusicController {
    static let shared = AppleMusicController()

    private let player = MPMusicPlayerController.applicationMusicPlayer
    private let systemPlayer = MPMusicPlayerController.systemMusicPlayer
    private(set) var hasActiveManagedPlayback = false
    private var didPrewarm = false

    private enum ManagedController {
        case none
        case application
        case system
    }

    private var managedController: ManagedController = .none

    private init() {}

    func prewarm() {
        #if DEBUG
        DebugServiceGuards.assertPhaseGate(.mediaPlayer, policy: .onBootAfterFirstFrame)
        #endif
        Diagnostics.log("AM.prewarm begin")
        guard !didPrewarm else {
            Diagnostics.log("AM.prewarm skipped (already)")
            return
        }
        didPrewarm = true
        DispatchQueue.global(qos: .utility).async { [player] in
            _ = player.playbackState
            player.beginGeneratingPlaybackNotifications()
            player.prepareToPlay()
            Diagnostics.log("AM.prewarm done")
        }
    }

    func play(item: MPMediaItem) {
        #if DEBUG
        DebugServiceGuards.assertPhaseGate(.mediaPlayer, policy: .onUserIntent)
        #endif
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            Diagnostics.log("AM.play(item) title=\(item.title ?? "nil") artist=\(item.artist ?? "nil")")
            self.player.setQueue(with: MPMediaItemCollection(items: [item]))
            self.player.prepareToPlay()
            self.player.play()
        }
        managedController = .application
        hasActiveManagedPlayback = true
    }

    func play(storeID: String) {
        #if DEBUG
        DebugServiceGuards.assertPhaseGate(.mediaPlayer, policy: .onUserIntent)
        #endif
        Diagnostics.log("AM.play(storeID) id=\(storeID)")
        let descriptor = MPMusicPlayerStoreQueueDescriptor(storeIDs: [storeID])
        systemPlayer.setQueue(with: descriptor)
        systemPlayer.play()
        managedController = .system
        hasActiveManagedPlayback = true
    }

    func play(reference: SongReference) {
        #if DEBUG
        DebugServiceGuards.assertPhaseGate(.mediaPlayer, policy: .onUserIntent)
        #endif
        switch reference.service {
        case .appleMusic:
            if let id = reference.appleMusicStoreID, !id.isEmpty {
                play(storeID: id)
            } else {
                Diagnostics.log("AM.play(reference) appleMusic missing storeID; ignoring")
            }
        case .spotify, .youtubeMusic:
            Diagnostics.log("AM.play(reference) unsupported service=\(String(describing: reference.service))")
        }
    }

    func pauseIfManaged() {
        #if DEBUG
        DebugServiceGuards.assertPhaseGate(.mediaPlayer, policy: .onUserIntent)
        #endif
        guard hasActiveManagedPlayback else { return }
        switch managedController {
        case .application:
            Diagnostics.log("AM.pauseIfManaged -> application")
            player.pause()
        case .system:
            Diagnostics.log("AM.pauseIfManaged -> system")
            systemPlayer.pause()
        case .none:
            break
        }
    }

    func resumeIfManaged() {
        #if DEBUG
        DebugServiceGuards.assertPhaseGate(.mediaPlayer, policy: .onUserIntent)
        #endif
        guard hasActiveManagedPlayback else { return }
        switch managedController {
        case .application:
            Diagnostics.log("AM.resumeIfManaged -> application")
            player.play()
        case .system:
            Diagnostics.log("AM.resumeIfManaged -> system")
            systemPlayer.play()
        case .none:
            break
        }
    }

    func skipToNext() {
        #if DEBUG
        DebugServiceGuards.assertPhaseGate(.mediaPlayer, policy: .onUserIntent)
        #endif
        guard hasActiveManagedPlayback else { return }
        switch managedController {
        case .application:
            Diagnostics.log("AM.skipToNext -> application")
            player.skipToNextItem()
            player.play()
        case .system:
            Diagnostics.log("AM.skipToNext -> system")
            systemPlayer.skipToNextItem()
            systemPlayer.play()
        case .none:
            break
        }
    }

    func skipToPrevious() {
        #if DEBUG
        DebugServiceGuards.assertPhaseGate(.mediaPlayer, policy: .onUserIntent)
        #endif
        guard hasActiveManagedPlayback else { return }
        switch managedController {
        case .application:
            Diagnostics.log("AM.skipToPrevious -> application")
            player.skipToPreviousItem()
            player.play()
        case .system:
            Diagnostics.log("AM.skipToPrevious -> system")
            systemPlayer.skipToPreviousItem()
            systemPlayer.play()
        case .none:
            break
        }
    }

    func stopManaging() {
        Diagnostics.log("AM.stopManaging")
        hasActiveManagedPlayback = false
        managedController = .none
    }

    func managedNowPlayingStoreID() -> String? {
        switch managedController {
        case .application:
            return player.nowPlayingItem?.playbackStoreID
        case .system:
            return systemPlayer.nowPlayingItem?.playbackStoreID
        case .none:
            return nil
        }
    }
}