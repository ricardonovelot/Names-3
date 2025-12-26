import Foundation

struct VideoAudioOverride: Codable, Equatable {
    var volume: Float?
    var song: SongReference?
    var updatedAt: Date
    var appleMusicStoreID: String?
}

extension Notification.Name {
    static let videoAudioOverrideChanged = Notification.Name("VideoAudioOverrideChanged")
}

actor VideoAudioOverrides {
    static let shared = VideoAudioOverrides()

    private var map: [String: VideoAudioOverride] = [:]
    private let defaultsKey = "video.audio.overrides.v1"
    private let maxEntries = 800

    init() {
        load()
    }

    func volumeOverride(for id: String?) -> Float? {
        guard let id, let e = map[id] else { return nil }
        return e.volume
    }

    func songReference(for id: String?) -> SongReference? {
        guard let id, let e = map[id] else { return nil }
        return e.song
    }

    func songOverride(for id: String?) -> String? {
        guard let id, let e = map[id] else { return nil }
        if let s = e.song?.appleMusicStoreID { return s }
        return e.appleMusicStoreID
    }

    func setVolumeOverride(for id: String, volume: Float?) {
        var v = min(max(volume ?? 0, 0), 1)
        if volume == nil {
            v = 0
        }
        var entry = map[id] ?? VideoAudioOverride(volume: nil, song: nil, updatedAt: Date(), appleMusicStoreID: nil)
        entry.volume = volume
        entry.updatedAt = Date()
        map[id] = entry
        trimIfNeeded()
        save()
        notifyChanged(id: id)
    }

    func setSongReference(for id: String, reference: SongReference?) {
        var entry = map[id] ?? VideoAudioOverride(volume: nil, song: nil, updatedAt: Date(), appleMusicStoreID: nil)
        entry.song = reference
        entry.updatedAt = Date()
        entry.appleMusicStoreID = nil
        map[id] = entry
        trimIfNeeded()
        save()
        notifyChanged(id: id)
    }

    func setSongOverride(for id: String, storeID: String?) {
        if let storeID {
            setSongReference(for: id, reference: SongReference.appleMusic(storeID: storeID))
        } else {
            setSongReference(for: id, reference: nil)
        }
    }

    private func notifyChanged(id: String) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .videoAudioOverrideChanged, object: nil, userInfo: ["id": id])
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(map)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            let loaded = try JSONDecoder().decode([String: VideoAudioOverride].self, from: data)
            var migrated: [String: VideoAudioOverride] = [:]
            for (k, var v) in loaded {
                if v.song == nil, let legacy = v.appleMusicStoreID, !legacy.isEmpty {
                    v.song = SongReference.appleMusic(storeID: legacy)
                    v.appleMusicStoreID = nil
                }
                migrated[k] = v
            }
            map = migrated
        } catch {
            map = [:]
        }
    }

    private func trimIfNeeded() {
        if map.count <= maxEntries { return }
        let sorted = map.sorted { $0.value.updatedAt < $1.value.updatedAt }
        for (k, _) in sorted.prefix(map.count - maxEntries) {
            map.removeValue(forKey: k)
        }
    }
}