import Foundation
import MediaPlayer
import MusicKit

struct AppleCatalogSong: Sendable, Hashable {
    let storeID: String
    let title: String
    let artist: String
    let duration: TimeInterval?
    let artworkURL: URL?
    let storefront: String
}

actor AppleMusicCatalog {
    static let shared = AppleMusicCatalog()

    /// MusicKit handles authentication; no developer token required.
    nonisolated static var isConfigured: Bool { true }

    func match(tracks: [YouTubeTrack], limit: Int = 3) async throws -> [AppleCatalogSong] {
        _ = Self.inferStorefront()
        var scored: [(AppleCatalogSong, Double)] = []

        for t in tracks {
            let candidates = try await searchSongs(title: t.title, artist: t.artist, limit: 5)
            let best = Self.pickBestCandidate(youtube: t, candidates: candidates)
            if let best {
                scored.append(best)
            }
        }

        let sorted = scored.sorted(by: { $0.1 > $1.1 }).map { $0.0 }
        var uniq: [AppleCatalogSong] = []
        var seen = Set<String>()
        for s in sorted {
            if !seen.contains(s.storeID) {
                uniq.append(s)
                seen.insert(s.storeID)
            }
            if uniq.count >= limit { break }
        }
        return uniq
    }

    // Public catalog search by free-form term
    func search(term: String, limit: Int = 15) async throws -> [AppleCatalogSong] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let storefront = Self.inferStorefront()
        do {
            let r = try await performCatalogSearch(term: trimmed, limit: limit)
            Diagnostics.log("AMCatalog.search ok storefront=\(storefront) count=\(r.count)")
            return r
        } catch {
            Diagnostics.log("AMCatalog.search error storefront=\(storefront) msg=\(error.localizedDescription)")
            throw error
        }
    }

    private func performCatalogSearch(term: String, limit: Int) async throws -> [AppleCatalogSong] {
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = limit
        let response = try await request.response()
        let storefront = Self.inferStorefront()
        return response.songs.map { song in
            mapSongToCatalog(song, storefront: storefront)
        }
    }

    private func searchSongs(title: String, artist: String, limit: Int) async throws -> [AppleCatalogSong] {
        let term = "\(artist) \(title)".trimmingCharacters(in: .whitespacesAndNewlines)
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = limit
        let response = try await request.response()
        let storefront = Self.inferStorefront()
        return response.songs.map { song in
            mapSongToCatalog(song, storefront: storefront)
        }
    }

    private func mapSongToCatalog(_ song: Song, storefront: String) -> AppleCatalogSong {
        let artURL = song.artwork?.url(width: 200, height: 200)
        return AppleCatalogSong(
            storeID: String(describing: song.id),
            title: song.title,
            artist: song.artistName,
            duration: song.duration,
            artworkURL: artURL,
            storefront: storefront
        )
    }

    private static func pickBestCandidate(youtube: YouTubeTrack, candidates: [AppleCatalogSong]) -> (AppleCatalogSong, Double)? {
        let ytTitle = normalize(youtube.title)
        let ytArtist = normalize(youtube.artist)
        let ytTitleWords = words(from: ytTitle)
        let ytArtistWords = words(from: ytArtist)

        var best: AppleCatalogSong?
        var bestScore: Double = 0

        for c in candidates {
            let cTitle = normalize(c.title)
            let cArtist = normalize(c.artist)
            let titleScore = jaccard(ytTitleWords, words(from: cTitle))
            let artistScore = jaccard(ytArtistWords, words(from: cArtist))
            var score = 0.7 * titleScore + 0.3 * artistScore

            if let ytDur = youtube.duration, let cDur = c.duration, ytDur > 1, cDur > 1 {
                let delta = abs(ytDur - cDur)
                if delta <= 3 { score += 0.2 }
                else if delta <= 8 { score += 0.1 }
                else if delta > 20 { score -= 0.2 }
            }

            if score > bestScore {
                bestScore = score
                best = c
            }
        }

        if let best, bestScore >= 0.45 {
            return (best, bestScore)
        }
        return nil
    }

    // Text utilities (mirrors SongMatcher)
    private static func normalize(_ s: String) -> String {
        var out = s.lowercased()
        let removals = ["(official video)", "(official audio)", "(lyrics)", "[official video]", "[official audio]", "[lyrics]"]
        removals.forEach { out = out.replacingOccurrences(of: $0, with: "") }
        out = out.replacingOccurrences(of: "\u{2019}", with: "'")
        out = out.replacingOccurrences(of: "\u{201C}", with: "\"")
        out = out.replacingOccurrences(of: "\u{201D}", with: "\"")
        out = out.replacingOccurrences(of: "&", with: "and")
        out = out.replacingOccurrences(of: "-", with: " ")
        out = out.replacingOccurrences(of: "_", with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(from s: String) -> Set<String> {
        Set(s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 })
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        let inter = a.intersection(b).count
        let uni = a.union(b).count
        return Double(inter) / Double(uni)
    }

    private static func inferStorefront() -> String {
        Locale.current.region?.identifier.lowercased() ?? "us"
    }
}
