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
    private var albumMap: [String: SongReference] = [:]
    private let defaultsKey = "video.audio.overrides.v1"
    private let albumDefaultsKey = "video.audio.overrides.album.v1"
    private let maxEntries = 800
    private let maxAlbumEntries = 200

    init() {
        Task { await load() }
    }

    func volumeOverride(for id: String?) -> Float? {
        guard let id, let e = map[id] else { return nil }
        return e.volume
    }

    /// Lookup: album first (if provided), then asset. Used when playing in album context.
    func songReference(for assetID: String?, albumIdentifier: String? = nil) -> SongReference? {
        if let albumId = albumIdentifier, albumId.hasPrefix("album:"), let ref = albumMap[albumId] {
            return ref
        }
        guard let id = assetID, let e = map[id] else { return nil }
        return e.song
    }

    /// Legacy: asset-only lookup (Photos feed).
    func songReference(for id: String?) -> SongReference? {
        songReference(for: id, albumIdentifier: nil)
    }

    func setSongReference(forAlbumIdentifier albumId: String, reference: SongReference?) {
        if let ref = reference {
            albumMap[albumId] = ref
        } else {
            albumMap.removeValue(forKey: albumId)
        }
        Diagnostics.log("Overrides.setSongReference album=\(albumId) ref=\(reference?.debugKey ?? "nil")")
        trimAlbumIfNeeded()
        saveAlbums()
        notifyChanged(id: albumId)
    }

    func songOverride(for id: String?) -> String? {
        guard let id, let e = map[id] else { return nil }
        if let s = e.song?.appleMusicStoreID { return s }
        return e.appleMusicStoreID
    }

    func setVolumeOverride(for id: String, volume: Float?) {
        let clampedVolume = volume.map { min(max($0, 0), 1) }
        var entry = map[id] ?? VideoAudioOverride(volume: nil, song: nil, updatedAt: Date(), appleMusicStoreID: nil)
        entry.volume = clampedVolume
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
        Diagnostics.log("Overrides.setSongReference id=\(id) ref=\(reference?.debugKey ?? "nil")")
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

    /// Returns recently used songs (assigned to videos/albums), sorted by most recent first.
    func recentlyUsedSongs(limit: Int = 25) async -> [SongReference] {
        var refs: [(SongReference, Date)] = []
        for (_, e) in map where e.song != nil {
            if let s = e.song, s.appleMusicStoreID != nil {
                refs.append((s, e.updatedAt))
            }
        }
        for (_, ref) in albumMap where ref.appleMusicStoreID != nil {
            refs.append((ref, Date()))
        }
        let sorted = refs.sorted { $0.1 > $1.1 }
        var seen = Set<String>()
        var result: [SongReference] = []
        for (r, _) in sorted {
            guard let id = r.appleMusicStoreID, !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(r)
            if result.count >= limit { break }
        }
        return result
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
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            loadAlbums()
            return
        }
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
        loadAlbums()
    }

    private func trimIfNeeded() {
        if map.count <= maxEntries { return }
        let sorted = map.sorted { $0.value.updatedAt < $1.value.updatedAt }
        for (k, _) in sorted.prefix(map.count - maxEntries) {
            map.removeValue(forKey: k)
        }
    }

    private func trimAlbumIfNeeded() {
        if albumMap.count <= maxAlbumEntries { return }
        let keys = Array(albumMap.keys)
        for k in keys.dropFirst(albumMap.count - maxAlbumEntries) {
            albumMap.removeValue(forKey: k)
        }
    }

    private func saveAlbums() {
        do {
            let data = try JSONEncoder().encode(albumMap)
            UserDefaults.standard.set(data, forKey: albumDefaultsKey)
        } catch {}
    }

    private func loadAlbums() {
        guard let data = UserDefaults.standard.data(forKey: albumDefaultsKey) else { return }
        do {
            albumMap = try JSONDecoder().decode([String: SongReference].self, from: data)
        } catch {
            albumMap = [:]
        }
    }
}