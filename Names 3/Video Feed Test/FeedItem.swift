import Photos

struct FeedItem {
    enum Kind {
        case video(PHAsset)
        case photoCarousel([PHAsset])
    }
    let id: String
    let kind: Kind

    /// Flattens FeedItems to [PHAsset] preserving order. Carousel shows one asset per page.
    /// .video(v) → [v], .photoCarousel([p1,p2]) → [p1,p2]
    static func flattenToAssets(_ items: [FeedItem]) -> [PHAsset] {
        items.flatMap { item in
            switch item.kind {
            case .video(let a): return [a]
            case .photoCarousel(let arr): return arr
            }
        }
    }

    static func video(_ asset: PHAsset) -> FeedItem {
        FeedItem(id: "v:\(asset.localIdentifier)", kind: .video(asset))
    }
    static func carousel(_ assets: [PHAsset]) -> FeedItem {
        let first = assets.first?.localIdentifier ?? UUID().uuidString
        return FeedItem(id: "c:\(first):\(assets.count)", kind: .photoCarousel(assets))
    }
}