import Foundation
import MediaPlayer
import Combine

@MainActor
final class AppleMusicManager: ObservableObject {
    @Published private(set) var authorization: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
    @Published private(set) var recentItems: [MPMediaItem] = []
    @Published private(set) var forYouItems: [MPMediaItem] = []

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

    func loadRecent(limit: Int = 50) {
        let query = MPMediaQuery.songs()
        guard let items = query.items, !items.isEmpty else {
            recentItems = []
            return
        }
        let sorted = items.sorted { lhs, rhs in
            lhs.dateAdded > rhs.dateAdded
        }
        let filtered = sorted.filter { $0.playbackDuration > 0.1 }
        recentItems = Array(filtered.prefix(limit))
    }

    /// Songs added to library around the same time as the asset was created (same month ± 1).
    func loadForYou(assetDate: Date, limit: Int = 25) {
        let query = MPMediaQuery.songs()
        guard let items = query.items, !items.isEmpty else {
            forYouItems = []
            return
        }
        let cal = Calendar.current
        let assetMonth = cal.component(.month, from: assetDate)
        let assetYear = cal.component(.year, from: assetDate)
        let filtered = items.filter { item in
            guard item.playbackDuration > 0.1 else { return false }
            let added = item.dateAdded
            let m = cal.component(.month, from: added)
            let y = cal.component(.year, from: added)
            if y == assetYear {
                return abs(m - assetMonth) <= 1
            }
            if abs(y - assetYear) == 1 {
                let (nearMonth, _) = y < assetYear ? (12, assetMonth) : (1, assetMonth)
                return m == nearMonth
            }
            return false
        }
        let sorted = filtered.sorted { $0.dateAdded > $1.dateAdded }
        forYouItems = Array(sorted.prefix(limit))
    }

    func play(item: MPMediaItem) {
        let player = MPMusicPlayerController.systemMusicPlayer
        let collection = MPMediaItemCollection(items: [item])
        player.setQueue(with: collection)
        player.play()
    }
}