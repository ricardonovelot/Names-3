import Foundation
import MediaPlayer

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


    nonisolated static var isConfigured: Bool {
        if let t = Bundle.main.object(forInfoDictionaryKey: "APPLE_MUSIC_DEVELOPER_TOKEN") as? String, !t.isEmpty {
            return true
        }
        return false
    }

    nonisolated static func currentDeveloperToken() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "APPLE_MUSIC_DEVELOPER_TOKEN") as? String
    }

    func match(tracks: [YouTubeTrack], limit: Int = 3) async throws -> [AppleCatalogSong] {
        guard let token = Self.currentDeveloperToken(), !token.isEmpty else {
            throw NSError(domain: "AppleMusicCatalog", code: -1, userInfo: [NSLocalizedDescriptionKey: "Developer token missing"])
        }
        let storefront = Self.inferStorefront() ?? "us"
        var scored: [(AppleCatalogSong, Double)] = []

        for t in tracks {
            let candidates = try await searchSongs(token: token, storefront: storefront, title: t.title, artist: t.artist, limit: 5)
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

    private func searchSongs(token: String, storefront: String, title: String, artist: String, limit: Int) async throws -> [AppleCatalogSong] {
        var comps = URLComponents(string: "https://api.music.apple.com/v1/catalog/\(storefront)/search")!
        let term = "\(artist) \(title)".trimmingCharacters(in: .whitespacesAndNewlines)
        comps.queryItems = [
            .init(name: "term", value: term),
            .init(name: "types", value: "songs"),
            .init(name: "limit", value: String(limit))
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw NSError(domain: "AppleMusicCatalog", code: status, userInfo: [NSLocalizedDescriptionKey: "Search failed \(status)"])
        }

        struct SearchResponse: Decodable {
            struct Results: Decodable {
                struct Songs: Decodable {
                    struct DataItem: Decodable {
                        struct Attributes: Decodable {
                            let name: String
                            let artistName: String
                            let durationInMillis: Double?
                            struct Artwork: Decodable { let url: String?; let width: Int?; let height: Int? }
                            let artwork: Artwork?
                        }
                        let id: String
                        let attributes: Attributes
                    }
                    let data: [DataItem]
                }
                let songs: Songs?
            }
            let results: Results?
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        let items = decoded.results?.songs?.data ?? []
        return items.map { item in
            let dur = item.attributes.durationInMillis.map { $0 / 1000.0 }
            let urlTemplate = item.attributes.artwork?.url
            let artURL = urlTemplate.flatMap { URL(string: $0.replacingOccurrences(of: "{w}", with: "200").replacingOccurrences(of: "{h}", with: "200")) }
            return AppleCatalogSong(
                storeID: item.id,
                title: item.attributes.name,
                artist: item.attributes.artistName,
                duration: dur,
                artworkURL: artURL,
                storefront: storefront
            )
        }
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

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        let inter = a.intersection(b).count
        let uni = a.union(b).count
        return Double(inter) / Double(uni)
    }

    private static func inferStorefront() -> String? {
        if let region = Locale.current.regionCode?.lowercased() {
            return region
        }
        return nil
    }
}