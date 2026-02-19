import Foundation
import SwiftUI
import Combine

@MainActor
final class DownloadTracker: ObservableObject {
    static let shared = DownloadTracker()

    enum Phase: String, Codable, Hashable {
        case prefetch
        case playerItem
        case ready
    }

    struct Entry: Identifiable {
        let id: String
        var phase: Phase
        var title: String
        var progress: Double
        var progressRatePercentPerSec: Double?
        var lastUpdate: Date
        var isComplete: Bool
        var isFailed: Bool
        var note: String?
        let createdAt: Date
        let seq: Int
    }

    @Published private(set) var entries: [Entry] = []

    private var lastProgressSnapshot: [String: (progress: Double, time: Date)] = [:]
    private let maxEntries = 50
    private var seqCounter = 0

    private init() {}

    func updateProgress(for id: String, phase: Phase, progress: Double, note: String? = nil) {
        let clamped = min(max(progress, 0), 1)
        let now = Date()

        let idx = ensureEntry(id, phase: phase, title: phase.rawValue)

        let prev = lastProgressSnapshot[id] ?? (entries[idx].progress, entries[idx].lastUpdate)
        let dt = now.timeIntervalSince(prev.time)
        let ratePctPerSec = dt > 0 ? ((clamped - prev.progress) * 100.0) / dt : nil

        entries[idx].phase = phase
        entries[idx].title = phase.rawValue
        entries[idx].progress = clamped
        entries[idx].progressRatePercentPerSec = ratePctPerSec
        entries[idx].lastUpdate = now
        entries[idx].isFailed = false
        entries[idx].note = note

        if phase == .ready {
            entries[idx].isComplete = true
            entries[idx].progress = 1.0
            entries[idx].progressRatePercentPerSec = nil
        }

        lastProgressSnapshot[id] = (entries[idx].progress, now)
        trimIfNeeded()
    }

    func markPlaybackReady(id: String) {
        let idx = ensureEntry(id, phase: .ready, title: Phase.ready.rawValue)
        entries[idx].phase = .ready
        entries[idx].title = Phase.ready.rawValue
        entries[idx].progress = 1.0
        entries[idx].isComplete = true
        entries[idx].isFailed = false
        entries[idx].progressRatePercentPerSec = nil
        entries[idx].lastUpdate = Date()
        lastProgressSnapshot[id] = (1.0, Date())
        trimIfNeeded()
    }

    func markComplete(id: String) {
        markPlaybackReady(id: id)
    }

    func markFailed(id: String, note: String? = nil) {
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].isFailed = true
            entries[i].lastUpdate = Date()
            entries[i].note = note
            lastProgressSnapshot[id] = (entries[i].progress, Date())
        } else {
            let now = Date()
            let e = Entry(id: id,
                          phase: .prefetch,
                          title: "Request",
                          progress: 0,
                          progressRatePercentPerSec: nil,
                          lastUpdate: now,
                          isComplete: false,
                          isFailed: true,
                          note: note,
                          createdAt: now,
                          seq: seqCounter)
            seqCounter &+= 1
            entries.append(e)
        }
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    private func ensureEntry(_ id: String, phase: Phase, title: String) -> Int {
        if let idx = entries.firstIndex(where: { $0.id == id }) {
            return idx
        }
        let now = Date()
        let e = Entry(id: id,
                      phase: phase,
                      title: title,
                      progress: 0,
                      progressRatePercentPerSec: nil,
                      lastUpdate: now,
                      isComplete: false,
                      isFailed: false,
                      note: nil,
                      createdAt: now,
                      seq: seqCounter)
        seqCounter &+= 1
        entries.append(e)
        return entries.count - 1
    }
}