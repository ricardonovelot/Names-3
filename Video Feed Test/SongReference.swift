import Foundation

enum SongServiceKind: String, Codable, Sendable {
    case appleMusic
    case spotify
    case youtubeMusic
}

struct SongReference: Codable, Equatable, Hashable, Sendable {
    var service: SongServiceKind
    var universalISRC: String?
    var appleMusicStoreID: String?
    var spotifyID: String?
    var title: String?
    var artist: String?

    static func appleMusic(storeID: String, title: String? = nil, artist: String? = nil, isrc: String? = nil) -> SongReference {
        SongReference(service: .appleMusic, universalISRC: isrc, appleMusicStoreID: storeID, spotifyID: nil, title: title, artist: artist)
    }

    var debugKey: String {
        switch service {
        case .appleMusic:
            return "apple:\(appleMusicStoreID ?? "nil")|isrc:\(universalISRC ?? "nil")"
        case .spotify:
            return "spotify:\(spotifyID ?? "nil")|isrc:\(universalISRC ?? "nil")"
        case .youtubeMusic:
            return "ytm|isrc:\(universalISRC ?? "nil")"
        }
    }
}