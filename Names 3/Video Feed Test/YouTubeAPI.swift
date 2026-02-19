import Foundation

struct YouTubeTrack: Sendable {
    let title: String
    let artist: String
    let duration: TimeInterval?
}

actor YouTubeAPI {
    static let shared = YouTubeAPI()

    enum APIError: LocalizedError {
        case http(Int, String, String?)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .http(let code, let message, let reason):
                if let reason {
                    return "YouTube API error \(code): \(message) (\(reason))"
                } else {
                    return "YouTube API error \(code): \(message)"
                }
            case .invalidResponse:
                return "YouTube API invalid response"
            }
        }
    }

    func fetchRecentLikedTracks(limit: Int = 25) async throws -> [YouTubeTrack] {
        let capped = min(max(limit, 1), 50)
        Diagnostics.log("YouTubeAPI.fetchRecentLikedTracks: start limit=\(capped)")
        do {
            return try await fetchLikedViaMyRating(limit: capped)
        } catch let APIError.http(code, _, _) where code == 400 || code == 403 || code == 404 {
            Diagnostics.log("YouTubeAPI.fetchRecentLikedTracks: myRating fallback; code=\(code)")
            return try await fetchLikedViaLikesPlaylist(limit: capped)
        } catch {
            Diagnostics.log("YouTubeAPI.fetchRecentLikedTracks: error \(error.localizedDescription)")
            throw error
        }
    }

    private func fetchLikedViaMyRating(limit: Int) async throws -> [YouTubeTrack] {
        let token = try await GoogleAuth.shared.validAccessToken()
        Diagnostics.log("YouTubeAPI.myRating: request maxResults=\(limit)")

        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        comps.queryItems = [
            .init(name: "part", value: "snippet,contentDetails"),
            .init(name: "myRating", value: "like"),
            .init(name: "maxResults", value: String(limit))
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            let (message, reason) = Self.parseGoogleError(from: data)
            Diagnostics.log("YouTubeAPI.myRating: http \(status) message=\(String(describing: message)) reason=\(String(describing: reason))")
            throw APIError.http(status, message ?? "Failed to fetch likes", reason)
        }

        struct Response: Decodable {
            struct Item: Decodable {
                struct Snippet: Decodable { let title: String; let channelTitle: String }
                struct ContentDetails: Decodable { let duration: String }
                let snippet: Snippet
                let contentDetails: ContentDetails
            }
            let items: [Item]
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.items.map { item in
            let (song, artist) = Self.extractSongArtist(from: item.snippet.title, channel: item.snippet.channelTitle)
            let dur = Self.parseISO8601Duration(item.contentDetails.duration)
            return YouTubeTrack(title: song, artist: artist, duration: dur)
        }
    }

    private func fetchLikedViaLikesPlaylist(limit: Int) async throws -> [YouTubeTrack] {
        let token = try await GoogleAuth.shared.validAccessToken()
        Diagnostics.log("YouTubeAPI.likesPlaylist: start")

        // 1) Mine channel details
        var channels = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")!
        channels.queryItems = [
            .init(name: "part", value: "contentDetails"),
            .init(name: "mine", value: "true")
        ]
        var chReq = URLRequest(url: channels.url!)
        chReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        chReq.setValue("application/json", forHTTPHeaderField: "Accept")

        let (chData, chResp) = try await URLSession.shared.data(for: chReq)
        let chStatus = (chResp as? HTTPURLResponse)?.statusCode ?? -1
        guard chStatus == 200 else {
            let (message, reason) = Self.parseGoogleError(from: chData)
            Diagnostics.log("YouTubeAPI.likesPlaylist: channels http \(chStatus) message=\(String(describing: message)) reason=\(String(describing: reason))")
            throw APIError.http(chStatus, message ?? "Failed to fetch channel", reason)
        }
        struct ChannelsResp: Decodable {
            struct Item: Decodable {
                struct ContentDetails: Decodable {
                    struct Related: Decodable { let likes: String? }
                    let relatedPlaylists: Related
                }
                let contentDetails: ContentDetails
            }
            let items: [Item]
        }
        let chDecoded = try JSONDecoder().decode(ChannelsResp.self, from: chData)
        guard let likesPlaylistId = chDecoded.items.first?.contentDetails.relatedPlaylists.likes, !likesPlaylistId.isEmpty else {
            throw APIError.invalidResponse
        }

        // 2) Playlist items to get recent liked video IDs
        var pl = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")!
        pl.queryItems = [
            .init(name: "part", value: "snippet,contentDetails"),
            .init(name: "playlistId", value: likesPlaylistId),
            .init(name: "maxResults", value: String(limit))
        ]
        var plReq = URLRequest(url: pl.url!)
        plReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        plReq.setValue("application/json", forHTTPHeaderField: "Accept")

        let (plData, plResp) = try await URLSession.shared.data(for: plReq)
        let plStatus = (plResp as? HTTPURLResponse)?.statusCode ?? -1
        guard plStatus == 200 else {
            let (message, reason) = Self.parseGoogleError(from: plData)
            Diagnostics.log("YouTubeAPI.likesPlaylist: playlistItems http \(plStatus) message=\(String(describing: message)) reason=\(String(describing: reason))")
            throw APIError.http(plStatus, message ?? "Failed to fetch liked playlist items", reason)
        }
        struct PLResp: Decodable {
            struct Item: Decodable {
                struct Snippet: Decodable { let title: String; let channelTitle: String }
                struct ContentDetails: Decodable { let videoId: String }
                let snippet: Snippet
                let contentDetails: ContentDetails
            }
            let items: [Item]
        }
        let plDecoded = try JSONDecoder().decode(PLResp.self, from: plData)
        let ids = plDecoded.items.map { $0.contentDetails.videoId }.filter { !$0.isEmpty }
        guard !ids.isEmpty else { return [] }

        // 3) Fetch video details for durations (batch up to 50 ids)
        var vids = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        vids.queryItems = [
            .init(name: "part", value: "snippet,contentDetails"),
            .init(name: "id", value: ids.joined(separator: ",")),
            .init(name: "maxResults", value: String(min(limit, ids.count)))
        ]
        var vReq = URLRequest(url: vids.url!)
        vReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        vReq.setValue("application/json", forHTTPHeaderField: "Accept")

        let (vData, vResp) = try await URLSession.shared.data(for: vReq)
        let vStatus = (vResp as? HTTPURLResponse)?.statusCode ?? -1
        guard vStatus == 200 else {
            let (message, reason) = Self.parseGoogleError(from: vData)
            Diagnostics.log("YouTubeAPI.likesPlaylist: videos http \(vStatus) message=\(String(describing: message)) reason=\(String(describing: reason))")
            throw APIError.http(vStatus, message ?? "Failed to fetch video details", reason)
        }
        struct VResp: Decodable {
            struct Item: Decodable {
                struct Snippet: Decodable { let title: String; let channelTitle: String }
                struct ContentDetails: Decodable { let duration: String }
                let snippet: Snippet
                let contentDetails: ContentDetails
            }
            let items: [Item]
        }
        let vDecoded = try JSONDecoder().decode(VResp.self, from: vData)
        let tracks: [YouTubeTrack] = vDecoded.items.map { item in
            let (song, artist) = Self.extractSongArtist(from: item.snippet.title, channel: item.snippet.channelTitle)
            let dur = Self.parseISO8601Duration(item.contentDetails.duration)
            return YouTubeTrack(title: song, artist: artist, duration: dur)
        }
        return Array(tracks.prefix(limit))
    }

    private static func parseGoogleError(from data: Data) -> (String?, String?) {
        struct GError: Decodable {
            struct Inner: Decodable { let code: Int?; let message: String?; let errors: [Detail]? }
            struct Detail: Decodable { let reason: String?; let message: String? }
            let error: Inner?
        }
        if let ge = try? JSONDecoder().decode(GError.self, from: data) {
            let msg = ge.error?.message
            let reason = ge.error?.errors?.first?.reason
            return (msg, reason)
        }
        if let txt = String(data: data, encoding: .utf8), !txt.isEmpty {
            return (txt, nil)
        }
        return (nil, nil)
    }

    private static func extractSongArtist(from title: String, channel: String) -> (String, String) {
        let cleaned = title
            .replacingOccurrences(of: "(Official Video)", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "(Official Audio)", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "(Lyrics)", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "[Official Video]", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "[Official Audio]", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "[Lyrics]", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " - Topic", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let dash = cleaned.firstIndex(of: "-") {
            let artist = cleaned[..<dash].trimmingCharacters(in: .whitespaces)
            let song = cleaned[cleaned.index(after: dash)...].trimmingCharacters(in: .whitespaces)
            return (song, artist)
        }
        return (cleaned, channel.replacingOccurrences(of: " - Topic", with: ""))
    }

    private static func parseISO8601Duration(_ str: String) -> TimeInterval? {
        var hours = 0, minutes = 0, seconds = 0
        let scanner = Scanner(string: str)
        guard scanner.scanString("P", into: nil),
              scanner.scanString("T", into: nil) else { return nil }
        var value: NSString?
        if scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "HMS"), into: &value) {
            if scanner.scanString("H", into: nil) { hours = Int(value! as String) ?? 0 }
            else if scanner.scanString("M", into: nil) { minutes = Int(value! as String) ?? 0 }
            else if scanner.scanString("S", into: nil) { seconds = Int(value! as String) ?? 0 }
        }
        while !scanner.isAtEnd {
            if scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "HMS"), into: &value) {
                if scanner.scanString("H", into: nil) { hours = Int(value! as String) ?? 0 }
                else if scanner.scanString("M", into: nil) { minutes = Int(value! as String) ?? 0 }
                else if scanner.scanString("S", into: nil) { seconds = Int(value! as String) ?? 0 }
            } else {
                break
            }
        }
        return TimeInterval(hours * 3600 + minutes * 60 + seconds)
    }
}