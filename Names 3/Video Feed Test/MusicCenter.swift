import Foundation
import Combine
import MediaPlayer

@MainActor
final class MusicCenter: ObservableObject {
    static let shared = MusicCenter()
    @Published private(set) var isReady: Bool = false
    @Published private(set) var isPlaying: Bool = false

    private var token: AnyCancellable?

    func attachIfNeeded() {
        guard !isReady else { return }
        _ = MusicPlaybackMonitor.shared
        token = MusicPlaybackMonitor.shared.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                self?.isPlaying = playing
            }
        isReady = true
        Diagnostics.log("MusicCenter: attached to MusicPlaybackMonitor")
    }

    deinit {
        token?.cancel()
        token = nil
    }
}