import UIKit
import Photos

// MARK: - Feed Architecture Provider Protocol

@MainActor
protocol FeedArchitectureProvider: AnyObject {
    var coordinator: CombinedMediaCoordinator? { get set }
    var isFeedVisible: Bool { get set }
    var currentFeedItems: [FeedItem] { get }
    func refreshVisibleCellsActiveState()
    func injectFromCarousel(assets: [PHAsset], scrollToAssetID: String?)
    /// Scroll to top (index 0, most recent). Called when user taps the already-selected Photos tab.
    func scrollToTop()
}

extension FeedArchitectureProvider {
    func scrollToTop() {}
}

typealias FeedViewController = UIViewController & FeedArchitectureProvider

// MARK: - Architecture Mode

enum FeedArchitectureMode: String, CaseIterable, Identifiable {
    case original            = "Original"
    case reactivePipeline    = "Reactive Pipeline"
    case actorPool           = "Actor Pool"
    case slidingWindow       = "Sliding Window"
    case snapshotDiff        = "Snapshot Diff"
    case aheadOfTime         = "Ahead-of-Time"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .original:         return "ViewModel + UICollectionView paging"
        case .reactivePipeline: return "Combine publisher chain with back-pressure"
        case .actorPool:        return "Actor isolation + TaskGroup parallelism"
        case .slidingWindow:    return "O(1) memory virtual scroll + ring buffer"
        case .snapshotDiff:     return "NSDiffableDataSource with day sections"
        case .aheadOfTime:      return "Precomputed persistent manifest, instant open"
        }
    }

    // MARK: Persistence

    static let userDefaultsKey = "Names3.FeedArchitectureMode"

    static var current: FeedArchitectureMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let mode = FeedArchitectureMode(rawValue: raw) else { return .original }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }

    // MARK: Factory

    @MainActor
    func makeFeedViewController() -> FeedViewController {
        switch self {
        case .original:         return TikTokFeedViewController()
        case .reactivePipeline: return Arch1_ReactivePipelineFeedVC()
        case .actorPool:        return Arch2_ActorPoolFeedVC()
        case .slidingWindow:    return Arch3_SlidingWindowFeedVC()
        case .snapshotDiff:     return Arch4_SnapshotDiffFeedVC()
        case .aheadOfTime:      return Arch5_AheadOfTimeFeedVC()
        }
    }
}

// MARK: - Shared Cell Builder

@MainActor
enum FeedCellBuilder {
    static func buildContent(
        for item: FeedItem,
        isActive: Bool,
        unbindCoordinator: StrictUnbindCoordinator
    ) -> UIView {
        switch item.kind {
        case .video(let asset):
            return FeedImpl5CellView(asset: asset, isActive: isActive, coordinator: unbindCoordinator)
        case .photoCarousel(let assets):
            if FeatureFlags.enablePhotoPosts || !assets.isEmpty {
                return MediaFeedCellView(content: .photoCarousel(assets))
            }
            return UIView()
        }
    }
}

// MARK: - Shared Data Helpers

enum FeedDataHelpers {
    static func fetchVideos() -> PHFetchResult<PHAsset> {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(
            format: "mediaType == %d AND duration >= 1.0",
            PHAssetMediaType.video.rawValue
        )
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: opts)
    }

    static func fetchPhotosAround(
        videos: [PHAsset],
        limit: Int,
        usedPhotoIDs: Set<String>
    ) -> [PHAsset] {
        guard FeedPhotoGroupingMode.current != .off,
              FeatureFlags.enablePhotoPosts else { return [] }
        let dates = videos.compactMap(\.creationDate)
        guard let min = dates.min(), let max = dates.max() else { return [] }
        let result = fetchPhotosBetween(minDate: min, maxDate: max, limit: limit, toleranceDays: 7, usedPhotoIDs: usedPhotoIDs)
        if !result.isEmpty { return result }
        return fetchPhotosBetween(minDate: min, maxDate: max, limit: limit, toleranceDays: 30, usedPhotoIDs: usedPhotoIDs)
    }

    static func fetchPhotosBetween(
        minDate: Date, maxDate: Date,
        limit: Int, toleranceDays: Int,
        usedPhotoIDs: Set<String>
    ) -> [PHAsset] {
        let tol = TimeInterval(toleranceDays * 86400)
        let lower = minDate.addingTimeInterval(-tol)
        let upper = maxDate.addingTimeInterval(tol)
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
            PHAssetMediaType.image.rawValue, lower as NSDate, upper as NSDate
        )
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetchLimit = limit * 3
        let result = PHAsset.fetchAssets(with: opts)
        let count = Swift.min(fetchLimit, result.count)
        guard count > 0 else { return [] }
        let slice = result.objects(at: IndexSet(integersIn: 0..<count))
        let filtered = slice.filter { asset in
            !usedPhotoIDs.contains(asset.localIdentifier) &&
            !ExcludeScreenshotsPreference.shouldExcludeAsScreenshot(asset)
        }
        return Array(filtered.prefix(limit))
    }

    static func filterHidden(_ videos: [PHAsset]) -> [PHAsset] {
        let hidden = DeletedVideosStore.snapshot()
        if hidden.isEmpty { return videos }
        return videos.filter { !hidden.contains($0.localIdentifier) }
    }

    static func makeCarousels(from photos: [PHAsset]) -> [[PHAsset]] {
        let mode = FeedPhotoGroupingMode.current
        guard mode != .off, FeatureFlags.enablePhotoPosts, !photos.isEmpty else { return [] }
        let gapMinutes = 60
        let gap = TimeInterval(gapMinutes * 60)
        var res: [[PHAsset]] = []
        var current: [PHAsset] = []
        var lastDate: Date?
        let sorted = photos.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        for a in sorted {
            let d = a.creationDate ?? .distantPast
            if let last = lastDate, last.timeIntervalSince(d) > gap, !current.isEmpty {
                let sampled = CarouselSampling.sample(current, mode: CarouselSamplingSettings.mode)
                if sampled.count >= 2 { res.append(sampled) }
                current = []
            }
            lastDate = d
            current.append(a)
        }
        if !current.isEmpty {
            let sampled = CarouselSampling.sample(current, mode: CarouselSamplingSettings.mode)
            if sampled.count >= 2 { res.append(sampled) }
        }
        return res
    }

    static func interleave(videos: [PHAsset], carousels: [[PHAsset]]) -> [FeedItem] {
        var out: [FeedItem] = []
        var cIdx = 0
        for v in videos {
            out.append(.video(v))
            if cIdx < carousels.count {
                out.append(.carousel(carousels[cIdx]))
                cIdx += 1
            }
        }
        return out
    }

    static func buildFeedItemsFromMixedAssets(_ assets: [PHAsset]) -> [FeedItem] {
        let hidden = DeletedVideosStore.snapshot()
        var out: [FeedItem] = []
        var photoBuffer: [PHAsset] = []
        for a in assets {
            switch a.mediaType {
            case .video:
                if !hidden.contains(a.localIdentifier) {
                    if !photoBuffer.isEmpty {
                        out.append(.carousel(photoBuffer))
                        photoBuffer = []
                    }
                    out.append(.video(a))
                }
            case .image:
                photoBuffer.append(a)
            default:
                break
            }
        }
        if !photoBuffer.isEmpty {
            out.append(.carousel(photoBuffer))
        }
        return out
    }

    /// Target size for photo preheat/request that matches what MediaFeedCellView actually requests.
    /// Must match exactly for PHCachingImageManager cache hits.
    @MainActor static func photoDisplayTargetSize(viewportPx: CGSize) -> CGSize {
        let horizontalPadding: CGFloat = 32
        let maxHeightFraction: CGFloat = 0.7
        let w = max(1, viewportPx.width - horizontalPadding)
        let h = max(1, viewportPx.height * maxHeightFraction)
        return CGSize(width: min(w, 2048), height: min(h, 2048))
    }

    @MainActor static func prefetchAssets(for items: [FeedItem], in indices: IndexSet, viewportPx: CGSize) {
        var videoAssets: [PHAsset] = []
        var carouselGroups: [[PHAsset]] = []
        for i in indices where items.indices.contains(i) {
            switch items[i].kind {
            case .video(let a): videoAssets.append(a)
            case .photoCarousel(let list):
                if FeatureFlags.enablePhotoPosts { carouselGroups.append(list) }
            }
        }
        if !videoAssets.isEmpty {
            VideoPrefetcher.shared.prefetch(videoAssets)
            PlayerItemPrefetcher.shared.prefetch(videoAssets)
        }
        if !carouselGroups.isEmpty {
            let targetSize = photoDisplayTargetSize(viewportPx: viewportPx)
            let thumbnailSize = CGSize(width: 400, height: 400)
            var allPhotos: [PHAsset] = []
            for group in carouselGroups {
                allPhotos.append(contentsOf: group)
            }
            ImagePrefetcher.shared.preheat(allPhotos, targetSize: targetSize)
            ImagePrefetcher.shared.preheat(allPhotos, targetSize: thumbnailSize)
            warmCarouselPhotos(groups: carouselGroups, targetSize: targetSize)
        }
    }

    @MainActor static func cancelPrefetch(for items: [FeedItem], in indices: IndexSet, viewportPx: CGSize) {
        var videoAssets: [PHAsset] = []
        var photoAssets: [PHAsset] = []
        for i in indices where items.indices.contains(i) {
            switch items[i].kind {
            case .video(let a): videoAssets.append(a)
            case .photoCarousel(let list):
                if FeatureFlags.enablePhotoPosts { photoAssets.append(contentsOf: list) }
            }
        }
        if !videoAssets.isEmpty {
            VideoPrefetcher.shared.cancel(videoAssets)
            PlayerItemPrefetcher.shared.cancel(videoAssets)
        }
        if !photoAssets.isEmpty {
            let targetSize = photoDisplayTargetSize(viewportPx: viewportPx)
            let thumbnailSize = CGSize(width: 400, height: 400)
            ImagePrefetcher.shared.stopPreheating(photoAssets, targetSize: targetSize)
            ImagePrefetcher.shared.stopPreheating(photoAssets, targetSize: thumbnailSize)
        }
    }

    static func itemContainsAsset(_ item: FeedItem, assetID: String) -> Bool {
        switch item.kind {
        case .video(let a): return a.localIdentifier == assetID
        case .photoCarousel(let arr): return arr.contains { $0.localIdentifier == assetID }
        }
    }

    /// Pre-request and decode the first few photos in each carousel group so they're in memory
    /// with decoded bitmaps ready when the cell appears. This eliminates the
    /// PHImageManager round-trip + main-thread decode that causes visible loading spinners.
    @MainActor private static func warmCarouselPhotos(groups: [[PHAsset]], targetSize: CGSize) {
        let maxGroupsToWarm = 3
        let maxPhotosPerGroup = 4
        for group in groups.prefix(maxGroupsToWarm) {
            for asset in group.prefix(maxPhotosPerGroup) {
                let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
                if ImageCacheService.shared.image(for: cacheKey) != nil { continue }
                Task { @MainActor in
                    let image = await ImagePrefetcher.shared.requestImage(for: asset, targetSize: targetSize)
                    guard let image else { return }
                    let decoded = await ImageDecodingService.decodeForDisplay(image)
                    if let decoded {
                        ImageCacheService.shared.setImage(decoded, for: cacheKey)
                    }
                }
            }
        }
    }
}
