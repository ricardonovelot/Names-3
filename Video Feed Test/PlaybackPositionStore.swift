import Foundation
import AVFoundation

actor PlaybackPositionStore {
    static let shared = PlaybackPositionStore()

    struct Entry {
        var seconds: Double
        var durationSeconds: Double
        var updatedAt: Date
    }

    private var map: [String: Entry] = [:]
    private let maxEntries = 400

    func record(id: String, time: CMTime, duration: CMTime) {
        let now = Date()
        let dur = duration.seconds.isFinite ? max(duration.seconds, 0) : 0
        var sec = time.seconds.isFinite ? max(time.seconds, 0) : 0
        if dur > 0 {
            sec = min(sec, max(dur - 0.1, 0)) // avoid pinning at exact end
        }
        map[id] = Entry(seconds: sec, durationSeconds: dur, updatedAt: now)
        trimIfNeeded()
    }

    func position(for id: String, duration: CMTime) -> CMTime? {
        guard let e = map[id] else { return nil }
        let dur = duration.seconds.isFinite ? duration.seconds : e.durationSeconds
        guard dur > 0 else {
            return e.seconds > 0.5 ? CMTime(seconds: e.seconds, preferredTimescale: 600) : nil
        }
        // If the saved position is near the start, ignore; near the end, clamp to zero.
        if e.seconds < 0.5 { return nil }
        if e.seconds >= dur - 0.25 { return CMTime.zero }
        return CMTime(seconds: e.seconds, preferredTimescale: 600)
    }

    func clear(id: String) {
        map.removeValue(forKey: id)
    }

    private func trimIfNeeded() {
        if map.count <= maxEntries { return }
        // Remove oldest entries
        let sorted = map.sorted { $0.value.updatedAt < $1.value.updatedAt }
        let toDrop = sorted.prefix(map.count - maxEntries)
        for (k, _) in toDrop {
            map.removeValue(forKey: k)
        }
    }
}