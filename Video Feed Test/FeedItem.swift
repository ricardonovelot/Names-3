import Photos

struct FeedItem {
    enum Kind {
        case video(PHAsset)
        case photoCarousel([PHAsset])
    }
    let id: String
    let kind: Kind
    
    static func video(_ asset: PHAsset) -> FeedItem {
        FeedItem(id: "v:\(asset.localIdentifier)", kind: .video(asset))
    }
    static func carousel(_ assets: [PHAsset]) -> FeedItem {
        let first = assets.first?.localIdentifier ?? UUID().uuidString
        return FeedItem(id: "c:\(first):\(assets.count)", kind: .photoCarousel(assets))
    }
}