import Foundation
import MediaPlayer
import Combine

@MainActor
final class AppleMusicManager: ObservableObject {
    @Published private(set) var authorization: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
    @Published private(set) var recentItems: [MPMediaItem] = []

    init() {
        if authorization == .authorized {
            loadRecent()
        }
    }

    func refreshAuthorization() {
        authorization = MPMediaLibrary.authorizationStatus()
    }

    func requestAuthorization() {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.authorization = status
                if status == .authorized {
                    self?.loadRecent()
                }
            }
        }
    }

    func loadRecent(limit: Int = 3) {
        let query = MPMediaQuery.songs()
        guard let items = query.items, !items.isEmpty else {
            recentItems = []
            return
        }
        let sorted = items.sorted { lhs, rhs in
            let l = lhs.dateAdded
            let r = rhs.dateAdded
            return l > r
        }
        recentItems = Array(sorted.prefix(limit))
    }

    func play(item: MPMediaItem) {
        let player = MPMusicPlayerController.systemMusicPlayer
        let collection = MPMediaItemCollection(items: [item])
        player.setQueue(with: collection)
        player.play()
    }
}