import Foundation
import MediaPlayer

actor SongMatcher {
    static let shared = SongMatcher()

    func match(tracks: [YouTubeTrack], limit: Int = 3) async throws -> [MPMediaItem] {
        var results: [(MPMediaItem, Double)] = []

        for track in tracks {
            if let best = Self.findBestMatch(track: track) {
                results.append(best)
            }
        }

        let sorted = results
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }

        var unique: [MPMediaItem] = []
        var seen = Set<MPMediaEntityPersistentID>()
        for item in sorted {
            if !seen.contains(item.persistentID) {
                unique.append(item)
                seen.insert(item.persistentID)
            }
            if unique.count >= limit { break }
        }
        return unique
    }

    private static func findBestMatch(track: YouTubeTrack) -> (MPMediaItem, Double)? {
        let title = normalize(track.title)
        let artist = normalize(track.artist)

        var preds: [MPMediaPropertyPredicate] = []
        if !title.isEmpty {
            preds.append(MPMediaPropertyPredicate(value: track.title, forProperty: MPMediaItemPropertyTitle, comparisonType: .contains))
        }
        if !artist.isEmpty {
            preds.append(MPMediaPropertyPredicate(value: track.artist, forProperty: MPMediaItemPropertyArtist, comparisonType: .contains))
        }

        let query = MPMediaQuery.songs()
        for p in preds {
            query.addFilterPredicate(p)
        }

        guard let items = query.items, !items.isEmpty else { return nil }

        var bestItem: MPMediaItem?
        var bestScore: Double = 0

        for item in items {
            let iTitle = normalize(item.title ?? "")
            let iArtist = normalize(item.artist ?? "")
            let titleScore = jaccard(wordsA: words(from: title), wordsB: words(from: iTitle))
            let artistScore = jaccard(wordsA: words(from: artist), wordsB: words(from: iArtist))
            var score = 0.7 * titleScore + 0.3 * artistScore

            if let d = track.duration, d > 1, item.playbackDuration > 1 {
                let delta = abs(d - item.playbackDuration)
                if delta <= 3 { score += 0.2 }
                else if delta <= 8 { score += 0.1 }
                else if delta > 20 { score -= 0.2 }
            }

            if score > bestScore {
                bestScore = score
                bestItem = item
            }
        }

        if let bestItem, bestScore >= 0.45 {
            return (bestItem, bestScore)
        }
        return nil
    }

    private static func normalize(_ s: String) -> String {
        var out = s.lowercased()
        let removals = ["(official video)", "(official audio)", "(lyrics)", "[official video]", "[official audio]", "[lyrics]"]
        removals.forEach { out = out.replacingOccurrences(of: $0, with: "") }
        out = out.replacingOccurrences(of: "’", with: "'")
        out = out.replacingOccurrences(of: "“", with: "\"")
        out = out.replacingOccurrences(of: "”", with: "\"")
        out = out.replacingOccurrences(of: "&", with: "and")
        out = out.replacingOccurrences(of: "-", with: " ")
        out = out.replacingOccurrences(of: "_", with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(from s: String) -> Set<String> {
        Set(s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 })
    }

    private static func jaccard(wordsA: Set<String>, wordsB: Set<String>) -> Double {
        if wordsA.isEmpty || wordsB.isEmpty { return 0 }
        let inter = wordsA.intersection(wordsB).count
        let uni = wordsA.union(wordsB).count
        return Double(inter) / Double(uni)
    }
}