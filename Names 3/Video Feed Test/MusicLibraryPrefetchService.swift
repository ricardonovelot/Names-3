import Foundation
import MediaPlayer
import QuartzCore
import os.log

@MainActor
final class MusicLibraryPrefetchService: FeatureService {
    let key = "musicLibraryPrefetch"
    private var didStart = false

    func prepare() async {
        Diagnostics.log("MusicLibraryPrefetch prepare")
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        Diagnostics.log("MusicLibraryPrefetch start begin")

        let okFF = await PhaseGate.shared.waitUntil(.firstFrame, timeout: 30)
        let okActive = await PhaseGate.shared.waitUntilAppActive(timeout: 30)
        let finalFF = await PhaseGate.shared.hasReached(.firstFrame)
        let finalActive = await PhaseGate.shared.hasReached(.appActive)
        Diagnostics.log("MusicLibraryPrefetch gates: firstFrame=\(finalFF) appActive=\(finalActive) waitedFF=\(okFF) waitedActive=\(okActive)")
        guard finalFF && finalActive else {
            Diagnostics.log("MusicLibraryPrefetch deferring: gates not satisfied; skipping to avoid early MediaPlayer/Accounts")
            return
        }

        #if DEBUG
        DebugServiceGuards.assertPhaseGate(.mediaPlayer, policy: .onBootAfterFirstFrame)
        #endif

        let status = MPMediaLibrary.authorizationStatus()
        Diagnostics.log("MusicLibraryPrefetch auth=\(status.rawValue)")
        guard status == .authorized else {
            Diagnostics.log("MusicLibraryPrefetch skip (auth != authorized)")
            return
        }

        // MOVE heavy work off-main; make incremental selection without full sort.
        Task.detached(priority: .utility) {
            let t0 = CACurrentMediaTime()
            Diagnostics.log("MLP(bg) query.songs begin onMain=\(Thread.isMainThread)")
            let songs = MPMediaQuery.songs().items ?? []
            let tQ = CACurrentMediaTime()
            Diagnostics.log("MLP(bg) query.songs done count=\(songs.count) dt=\(String(format: "%.3f", tQ - t0))s")

            // Top-N by dateAdded without full sort (min-heap emulated with array scan)
            let N = 15
            var picks: [MPMediaItem] = []
            picks.reserveCapacity(N)

            func date(_ item: MPMediaItem) -> Date { item.dateAdded }
            for item in songs {
                if item.playbackDuration <= 0.1 { continue }
                if picks.count < N {
                    picks.append(item)
                } else {
                    // Find current minimum
                    var minIdx = 0
                    var minDate = date(picks[0])
                    for i in 1..<picks.count {
                        let d = date(picks[i])
                        if d < minDate {
                            minDate = d
                            minIdx = i
                        }
                    }
                    if date(item) > minDate {
                        picks[minIdx] = item
                    }
                }
                // Optional cooperative yield to keep QoS fair
                if picks.count % 200 == 0 {
                    await Task.yield()
                }
            }

            // Final descending order by dateAdded for presentation
            picks.sort { a, b in a.dateAdded > b.dateAdded }

            let tSel = CACurrentMediaTime()
            Diagnostics.log("MLP(bg) select topN=\(picks.count) dt=\(String(format: "%.3f", tSel - tQ))s total=\(String(format: "%.3f", tSel - t0))s")

            await MusicLibraryCache.shared.setLastAdded(picks)
            let tC = CACurrentMediaTime()
            Diagnostics.log("MLP(bg) cache set dt=\(String(format: "%.3f", tC - tSel))s total=\(String(format: "%.3f", tC - t0))s")
            Diagnostics.log("MusicLibraryPrefetch done (bg) cached=\(picks.count)")
        }
    }

    func stop() async { }
}