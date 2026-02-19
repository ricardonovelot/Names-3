import Foundation
import MediaPlayer

actor MusicLibraryCache {
    static let shared = MusicLibraryCache()
    private var lastAdded: [MPMediaItem] = []
    private var lastUpdated: Date?

    func setLastAdded(_ items: [MPMediaItem]) {
        lastAdded = items
        lastUpdated = Date()
        Diagnostics.log("MusicLibraryCache: cached lastAdded=\(items.count)")
    }

    func snapshotLastAdded() -> (items: [MPMediaItem], updatedAt: Date?) {
        (lastAdded, lastUpdated)
    }
}