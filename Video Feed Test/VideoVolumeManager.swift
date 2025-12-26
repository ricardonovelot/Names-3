import Foundation
import Combine
import AVFoundation

@MainActor
final class VideoVolumeManager: ObservableObject {
    static let shared = VideoVolumeManager()

    @Published var userVolume: Float {
        didSet {
            if userVolume != oldValue {
                UserDefaults.standard.set(userVolume, forKey: Self.kUserVolume)
                recompute()
            }
        }
    }

    @Published private(set) var effectiveVolume: Float = 1.0
    @Published private(set) var isMusicPlaying: Bool = false

    private static let defaultUserVolume: Float = 0.03
    private static let defaultUserVolumeWhileMusic: Float = 0.02

    let duckingCapWhileMusic: Float = 0.3

    private var cancellables = Set<AnyCancellable>()
    private static let kUserVolume = "video.volume.user"

    private static func clamp(_ value: Float) -> Float {
        min(max(value, 0.0), 1.0)
    }

    private static func resolvedUserVolume(isMusicPlaying: Bool, storedVolume: Float?) -> Float {
        if let storedVolume {
            return clamp(storedVolume)
        }
        return isMusicPlaying ? defaultUserVolumeWhileMusic : defaultUserVolume
    }

    private init() {
        let storedVolume = UserDefaults.standard.object(forKey: Self.kUserVolume) as? Float
        let musicPlaying = MusicPlaybackMonitor.shared.isPlaying

        self.userVolume = Self.resolvedUserVolume(isMusicPlaying: musicPlaying, storedVolume: storedVolume)
        self.isMusicPlaying = musicPlaying

        recompute()

        MusicPlaybackMonitor.shared.$isPlaying
            .sink { [weak self] playing in
                guard let self else { return }
                self.isMusicPlaying = playing
                self.recompute()
            }
            .store(in: &cancellables)
    }

    private func recompute() {
        if isMusicPlaying {
            effectiveVolume = min(userVolume, duckingCapWhileMusic)
        } else {
            effectiveVolume = userVolume
        }
    }

    func apply(to player: AVPlayer) {
        player.volume = effectiveVolume
    }
}