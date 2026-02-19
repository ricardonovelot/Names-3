import Foundation
import SwiftUI
import Photos
import AVFoundation
import Combine

@MainActor
final class TikTokFeedViewModel: ObservableObject {
    enum FeedMode {
        case start
        case explore
    }
    
    @Published var authorization: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var items: [FeedItem] = []
    @Published var isLoading: Bool = false
    @Published var initialIndexInWindow: Int?

    private let mode: FeedMode

    private var fetchVideos: PHFetchResult<PHAsset>?
    private let pageSizeVideos = 50
    private let pageSizePhotos = 60
    private let prefetchThreshold = 8

    private let interleaveEvery = 5
    private let carouselMin = 3
    private let carouselMax = 6
    
    private var videoCursor = 0
    private var videosSinceLastCarousel = 0
    private var usedPhotoIDs: Set<String> = []

    /// When true, we loaded via bridge (loadWindowContaining); skip loadMore until user-triggered load.
    private var isBridgeWindowActive = false

    // Day-hopping explore mode state
    private var exploreModeActive = false
    private var segmentEndIndices: [Int] = []
    private var exploredDayIndices: Set<Int> = []
    private var lastAppendedDayIndex: Int?
    // Explore prewarm state
    private var prewarmedNextDayIndex: Int?
    private var prewarmInFlight: Bool = false

    private struct DayRange {
        let dayStart: Date
        let start: Int   // inclusive in fetchVideos
        let end: Int     // exclusive in fetchVideos
    }
    private var dayRanges: [DayRange] = []
    
    /// When set before onAppear, the initial load uses this asset instead of loadRandomWindow (Carousel→Feed bridge).
    var initialBridgeAssetID: String?
    
    init(mode: FeedMode = .explore) {
        self.mode = mode
    }
    
    func onAppear() {
        requestAuthorizationAndLoad()
        Diagnostics.log("TikTokFeed onAppear")
        PlayerLeakDetector.shared.snapshotActive(log: true)
        configureAudioSession(active: true)
        NotificationCenter.default.addObserver(forName: .deletedVideosChanged, object: nil, queue: .main) { [weak self] _ in
            self?.handleDeletedVideosChanged()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .deletedVideosChanged, object: nil)
    }
    
    private func requestAuthorizationAndLoad() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorization = status
        Diagnostics.log("Auth: current=\(String(describing: status))")
        FirstLaunchProbe.shared.recordAuthInitial(status)

        guard status != .notDetermined else {
            FirstLaunchProbe.shared.recordAuthRequested()
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                Task { @MainActor [weak self] in
                    self?.authorization = newStatus
                    Diagnostics.log("Auth: requested -> \(String(describing: newStatus))")
                    FirstLaunchProbe.shared.recordAuthResult(newStatus)
                    if newStatus == .authorized || newStatus == .limited {
                        self?.loadWindowOrBridgeTarget()
                    }
                }
            }
            return
        }
        
        if status == .authorized || status == .limited {
            loadWindowOrBridgeTarget()
        }
    }
    
    func reload() {
        Diagnostics.log("Reload requested")
        loadWindow()
    }

    func startFromBeginning() {
        loadStartWindow()
    }
    
    private func loadWindow() {
        switch mode {
        case .start:
            loadStartWindow()
        case .explore:
            loadRandomWindow()
        }
    }

    /// Uses bridge target if set (Carousel→Feed); otherwise normal load.
    private func loadWindowOrBridgeTarget() {
        // #region agent log
        Diagnostics.debugBridge(hypothesisId: "C", location: "TikTokFeedViewModel.loadWindowOrBridgeTarget", message: "loadWindowOrBridgeTarget", data: ["initialBridgeAssetID": initialBridgeAssetID ?? "nil"])
        // #endregion
        if let id = initialBridgeAssetID {
            initialBridgeAssetID = nil
            Diagnostics.log("Feed: loading window for bridge target asset \(id)")
            loadWindowContaining(assetID: id)
        } else {
            loadWindow()
        }
    }

    private func filterHidden(_ videos: [PHAsset]) -> [PHAsset] {
        let hidden = DeletedVideosStore.snapshot()
        if hidden.isEmpty { return videos }
        return videos.filter { !hidden.contains($0.localIdentifier) }
    }
    
    private func commonFetchSetup() {
        isBridgeWindowActive = false
        let videoOpts = PHFetchOptions()
        videoOpts.predicate = NSPredicate(format: "mediaType == %d AND duration >= 1.0", PHAssetMediaType.video.rawValue)
        videoOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchVideos = PHAsset.fetchAssets(with: videoOpts)
        
        videoCursor = 0
        videosSinceLastCarousel = 0
        usedPhotoIDs.removeAll()

        // RESET day explore state
        dayRanges.removeAll()
        segmentEndIndices.removeAll()
        exploredDayIndices.removeAll()
        lastAppendedDayIndex = nil
        exploreModeActive = false
        // RESET prewarm
        prewarmedNextDayIndex = nil
        prewarmInFlight = false
    }

    // Build day ranges from the sorted fetch result (descending by creationDate)
    private func buildDayRangesIfNeeded() {
        guard dayRanges.isEmpty, let vResult = fetchVideos, vResult.count > 0 else { return }
        var ranges: [DayRange] = []
        var curStart = 0
        var curDayStart: Date?
        let cal = Calendar.current
        for i in 0..<vResult.count {
            let asset = vResult.object(at: i)
            guard let d = asset.creationDate else { continue }
            let dStart = cal.startOfDay(for: d)
            if curDayStart == nil {
                curDayStart = dStart
                curStart = i
            } else if dStart != curDayStart {
                ranges.append(DayRange(dayStart: curDayStart!, start: curStart, end: i))
                curDayStart = dStart
                curStart = i
            }
        }
        if let curDayStart {
            ranges.append(DayRange(dayStart: curDayStart, start: curStart, end: fetchVideos!.count))
        }
        dayRanges = ranges
        Diagnostics.log("DayRanges built count=\(dayRanges.count)")
    }

    // Biased pick favoring recent days to increase local/cache hit rate.
    // Strategy: sample up to 6 unseen day indices and take the minimum (newest).
    private func pickBiasedNextDayIndex() -> Int? {
        guard !dayRanges.isEmpty else { return nil }
        var candidates = Array(dayRanges.indices).filter { !exploredDayIndices.contains($0) }
        if candidates.isEmpty {
            exploredDayIndices.removeAll()
            candidates = Array(dayRanges.indices)
            if let last = lastAppendedDayIndex, candidates.count > 1 {
                candidates.removeAll { $0 == last }
            }
        }
        guard !candidates.isEmpty else { return nil }
        let sampleCount = min(6, candidates.count)
        var sample: [Int] = []
        for _ in 0..<sampleCount {
            if let pick = candidates.randomElement() { sample.append(pick) }
        }
        let chosen = sample.min()
        if let c = chosen {
            Diagnostics.log("ExploreBias: pickBiased dayIdx=\(c) of \(dayRanges.count) (sample=\(sample))")
        }
        return chosen
    }

    // Prewarm the next day early by prefetching the first few videos from that day.
    @discardableResult
    private func prewarmNextDayIfNeeded(biased: Bool = true) -> Int? {
        guard exploreModeActive, !prewarmInFlight, prewarmedNextDayIndex == nil else { return prewarmedNextDayIndex }
        guard let dayIdx = biased ? pickBiasedNextDayIndex() : pickNextRandomDayIndex() else { return nil }
        guard let vResult = fetchVideos, dayRanges.indices.contains(dayIdx) else { return nil }
        let r = dayRanges[dayIdx]
        let baseSlice = vResult.objects(at: IndexSet(integersIn: r.start..<r.end))
        let vSlice = filterHidden(baseSlice)
        guard !vSlice.isEmpty else {
            exploredDayIndices.insert(dayIdx)
            return nil
        }
        let prewarmCount = min(8, vSlice.count)
        let warm = Array(vSlice.prefix(prewarmCount))
        prewarmInFlight = true
        prewarmedNextDayIndex = dayIdx
        Diagnostics.log("ExplorePrewarm: start dayIdx=\(dayIdx) date=\(r.dayStart) warmCount=\(warm.count)")
        VideoPrefetcher.shared.prefetch(warm)
        PlayerItemPrefetcher.shared.prefetch(warm)
        // Note: we don't block; warming continues while user scrolls.
        return dayIdx
    }

    // Pick a random unseen day index; when exhausted, reset the explored set to continue
    private func pickNextRandomDayIndex() -> Int? {
        guard !dayRanges.isEmpty else { return nil }
        var candidates = Array(dayRanges.indices).filter { !exploredDayIndices.contains($0) }
        if candidates.isEmpty {
            // Reset but avoid immediately repeating the last day if possible
            exploredDayIndices.removeAll()
            candidates = Array(dayRanges.indices)
            if let last = lastAppendedDayIndex, candidates.count > 1 {
                candidates.removeAll { $0 == last }
            }
        }
        guard !candidates.isEmpty else { return nil }
        return candidates.randomElement()
    }

    // Append one day segment; returns true if items were appended
    private func appendDay(dayIndex: Int, asInitial: Bool) -> Bool {
        guard let vResult = fetchVideos, dayRanges.indices.contains(dayIndex) else { return false }
        let r = dayRanges[dayIndex]
        let baseSlice = vResult.objects(at: IndexSet(integersIn: r.start..<r.end))
        let vSlice = filterHidden(baseSlice)
        guard !vSlice.isEmpty else {
            Diagnostics.log("ExploreDay: skip empty/hidden day idx=\(dayIndex) date=\(r.dayStart)")
            exploredDayIndices.insert(dayIndex)
            return false
        }

        let pSlice = photosAround(for: vSlice, limit: pageSizePhotos)
        let carousels = makeCarousels(from: pSlice)

        let startStride = videosSinceLastCarousel
        let (built, _, newTailCount) = interleave(videos: vSlice, carousels: carousels, startVideoStride: startStride)

        if asInitial {
            items = built
            initialIndexInWindow = 0
            isLoading = false
            Diagnostics.log("ExploreDay: initial publish items=\(items.count) day=\(r.dayStart) videos=\(vSlice.count) carousels=\(carousels.count)")
            if let first = built.first {
                switch first.kind {
                case .video(let a):
                    FirstLaunchProbe.shared.windowPublished(items: built.count, firstID: a.localIdentifier)
                    VideoPrefetcher.shared.prefetch([a])
                    PlayerItemPrefetcher.shared.prefetch([a])
                case .photoCarousel(let arr):
                    FirstLaunchProbe.shared.windowPublished(items: built.count, firstID: arr.first?.localIdentifier ?? "n/a")
                }
            }
            // proactively prefetch a few more upcoming videos for the initial day
            let prewarmCount = min(6, vSlice.count)
            if prewarmCount > 1 {
                let extra = Array(vSlice.prefix(prewarmCount).dropFirst())
                VideoPrefetcher.shared.prefetch(extra)
                PlayerItemPrefetcher.shared.prefetch(extra)
            }
        } else {
            let before = items.count
            items.append(contentsOf: built)
            Diagnostics.log("ExploreDay: appended segment items+\(built.count) total=\(items.count) day=\(r.dayStart) videos=\(vSlice.count) carousels=\(carousels.count)")
            let appendedCount = items.count - before
            if appendedCount <= 0 {
                return false
            }
            // proactively prefetch the first N videos of the newly appended day
            let prewarmCount = min(8, vSlice.count)
            if prewarmCount > 0 {
                let warm = Array(vSlice.prefix(prewarmCount))
                VideoPrefetcher.shared.prefetch(warm)
                PlayerItemPrefetcher.shared.prefetch(warm)
            }
        }

        videosSinceLastCarousel = newTailCount
        markPhotosUsed(from: built)
        segmentEndIndices.append(items.count - 1)
        exploredDayIndices.insert(dayIndex)
        lastAppendedDayIndex = dayIndex
        // consumed prewarm if this was the prewarmed day
        if prewarmedNextDayIndex == dayIndex {
            prewarmedNextDayIndex = nil
            prewarmInFlight = false
            Diagnostics.log("ExplorePrewarm: consumed dayIdx=\(dayIndex)")
        }
        return true
    }
    
    private func loadStartWindow() {
        isLoading = true
        Diagnostics.log("StartWindow: begin")
        FirstLaunchProbe.shared.startWindowBegin()
        commonFetchSetup()
        
        guard let vResult = fetchVideos, vResult.count > 0 else {
            items = []
            isLoading = false
            initialIndexInWindow = nil
            Diagnostics.log("StartWindow: no video assets")
            return
        }
        
        let vEnd = min(pageSizeVideos, vResult.count)
        let vSliceBase = vResult.objects(at: IndexSet(integersIn: 0..<vEnd))
        let vSlice = filterHidden(vSliceBase)
        
        let pSlice = photosAround(for: vSlice, limit: pageSizePhotos)
        let carousels = makeCarousels(from: pSlice)
        let (itemsBuilt, _, videosTailCount) = interleave(videos: vSlice, carousels: carousels, startVideoStride: 0)
        
        items = itemsBuilt
        Diagnostics.log("StartWindow: publish items=\(items.count)")
        if let first = itemsBuilt.first {
            switch first.kind {
            case .video(let a):
                FirstLaunchProbe.shared.windowPublished(items: itemsBuilt.count, firstID: a.localIdentifier)
                VideoPrefetcher.shared.prefetch([a])
                PlayerItemPrefetcher.shared.prefetch([a])
            case .photoCarousel(let arr):
                FirstLaunchProbe.shared.windowPublished(items: itemsBuilt.count, firstID: arr.first?.localIdentifier ?? "n/a")
            }
        }
        initialIndexInWindow = 0
        isLoading = false
        
        videoCursor = vEnd
        videosSinceLastCarousel = videosTailCount
        markPhotosUsed(from: itemsBuilt)
        
        let firstID: String = {
            if let first = itemsBuilt.first {
                switch first.kind {
                case .video(let a): return a.localIdentifier
                case .photoCarousel(let arr): return arr.first?.localIdentifier ?? "n/a"
                }
            }
            return "n/a"
        }()
        Diagnostics.log("StartWindow: videosTotal=\(vResult.count) vWindow=\(vSlice.count) carousels=\(carousels.count) first=\(firstID)")
    }
    
    func loadRandomWindow() {
        isLoading = true
        Diagnostics.log("Explore: RandomDay begin")
        commonFetchSetup()
        guard let vResult = fetchVideos, vResult.count > 0 else {
            items = []
            isLoading = false
            initialIndexInWindow = nil
            Diagnostics.log("Explore: no video assets")
            return
        }
        buildDayRangesIfNeeded()
        guard !dayRanges.isEmpty else {
            items = []
            isLoading = false
            initialIndexInWindow = nil
            Diagnostics.log("Explore: no day ranges found")
            return
        }
        exploreModeActive = true
        // Always try the most recent day first; advance only if empty/hidden.
        var appended = false
        let tryCap = min(12, dayRanges.count)
        for dayIdx in 0..<tryCap {
            let d = dayRanges[dayIdx].dayStart
            Diagnostics.log("Explore: try initial newest day idx=\(dayIdx) date=\(d)")
            if appendDay(dayIndex: dayIdx, asInitial: true) {
                appended = true
                break
            }
        }
        if appended {
            _ = prewarmNextDayIfNeeded(biased: true)
        }
        if !appended {
            // Fallback to old behavior if all tried days are empty/hidden
            Diagnostics.log("Explore: fallback to legacy random window (no appendable newest days found)")
            exploreModeActive = false

            let vCount = vResult.count
            let windowSize = min(pageSizeVideos, vCount)
            let globalRandom = Int.random(in: 0..<vCount)
            let half = windowSize / 2
            var start = max(0, globalRandom - half)
            if start + windowSize > vCount {
                start = max(0, vCount - windowSize)
            }
            let end = min(vCount, start + windowSize)
            let vSliceBase = vResult.objects(at: IndexSet(integersIn: start..<end))
            let vSlice = filterHidden(vSliceBase)
            
            let pSlice = photosAround(for: vSlice, limit: pageSizePhotos)
            let carousels = makeCarousels(from: pSlice)
            let (itemsBuilt, _, videosTailCount) = interleave(videos: vSlice, carousels: carousels, startVideoStride: 0)
            
            items = itemsBuilt
            Diagnostics.log("RandomWindow(legacy): publish items=\(items.count)")
            if let first = itemsBuilt.first {
                switch first.kind {
                case .video(let a):
                    FirstLaunchProbe.shared.windowPublished(items: itemsBuilt.count, firstID: a.localIdentifier)
                case .photoCarousel(let arr):
                    FirstLaunchProbe.shared.windowPublished(items: itemsBuilt.count, firstID: arr.first?.localIdentifier ?? "n/a")
                }
            }
            initialIndexInWindow = 0
            isLoading = false
            
            videoCursor = end
            videosSinceLastCarousel = videosTailCount
            markPhotosUsed(from: itemsBuilt)
            
            let chosenID: String = {
                if let first = itemsBuilt.first {
                    switch first.kind {
                    case .video(let a): return a.localIdentifier
                    case .photoCarousel(let arr): return arr.first?.localIdentifier ?? "n/a"
                    }
                }
                return "n/a"
            }()
            Diagnostics.log("RandomWindow(legacy): totalVideos=\(vCount) window=[\(start)..<\(end)] first id=\(chosenID) carousels=\(carousels.count)")
        }
    }

    func loadWindow(around targetDate: Date, targetAssetID: String? = nil) {
        isLoading = true
        Diagnostics.log("DateWindow: begin target=\(targetDate) assetID=\(targetAssetID ?? "nil")")
        commonFetchSetup()
        guard let vResult = fetchVideos, vResult.count > 0 else {
            items = []
            isLoading = false
            initialIndexInWindow = nil
            Diagnostics.log("DateWindow: no video assets")
            return
        }
        let vCount = vResult.count
        var foundIndex = 0
        for i in 0..<vCount {
            if let d = vResult.object(at: i).creationDate, d <= targetDate {
                foundIndex = i
                break
            }
        }
        let windowSize = min(pageSizeVideos, vCount)
        let half = windowSize / 2
        var start = max(0, foundIndex - half)
        if start + windowSize > vCount {
            start = max(0, vCount - windowSize)
        }
        let end = min(vCount, start + windowSize)
        let vSliceBase = vResult.objects(at: IndexSet(integersIn: start..<end))
        let vSlice = filterHidden(vSliceBase)
        let pSlice = photosAround(for: vSlice, limit: pageSizePhotos)
        let carousels = makeCarousels(from: pSlice)
        let (itemsBuilt, _, videosTailCount) = interleave(videos: vSlice, carousels: carousels, startVideoStride: 0)

        let initialLocalIndex: Int = {
            if let targetID = targetAssetID, let idx = indexOfAssetInItems(targetID, items: itemsBuilt) {
                return idx
            }
            let clampedIndex = min(max(foundIndex, start), end - 1)
            let selectedID = vResult.object(at: clampedIndex).localIdentifier
            for (idx, it) in itemsBuilt.enumerated() {
                if case .video(let a) = it.kind, a.localIdentifier == selectedID {
                    return idx
                }
            }
            return 0
        }()

        items = itemsBuilt
        Diagnostics.log("DateWindow: publish items=\(items.count)")
        if let first = itemsBuilt.first {
            switch first.kind {
            case .video(let a):
                FirstLaunchProbe.shared.windowPublished(items: itemsBuilt.count, firstID: a.localIdentifier)
            case .photoCarousel(let arr):
                FirstLaunchProbe.shared.windowPublished(items: itemsBuilt.count, firstID: arr.first?.localIdentifier ?? "n/a")
            }
        }
        initialIndexInWindow = initialLocalIndex
        isLoading = false

        videoCursor = end
        videosSinceLastCarousel = videosTailCount
        markPhotosUsed(from: itemsBuilt)

        Diagnostics.log("DateWindow: target=\(targetDate) window=[\(start)..<\(end)] initialLocalIndex=\(initialLocalIndex) targetAssetID=\(targetAssetID ?? "nil")")
    }

    func jumpToOneYearAgo() {
        if let date = Calendar.current.date(byAdding: .year, value: -1, to: Date()) {
            loadWindow(around: date)
        } else {
            loadRandomWindow()
        }
    }

    /// Loads a window containing the given asset (for sync when switching from Carousel).
    /// Uses a unified mixed fetch (photos + videos, any duration) so the exact same asset is always shown.
    func loadWindowContaining(assetID: String) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            loadWindow()
            return
        }
        isLoading = true
        commonFetchSetup()
        Diagnostics.log("BridgeWindow: loading for asset \(assetID) mediaType=\(asset.mediaType.rawValue)")
        Task { @MainActor in
            let (mixedAssets, targetIdx) = await NameFacesCarouselAssetFetcher.fetchMixedAssetsAround(
                targetAsset: asset,
                rangeDays: 14,
                limit: 80
            )
            guard !mixedAssets.isEmpty else {
                Diagnostics.log("BridgeWindow: no assets, falling back to normal load")
                loadWindow(around: asset.creationDate ?? Date(), targetAssetID: assetID)
                return
            }
            let feedItems = self.buildFeedItemsFromMixedAssets(mixedAssets)
            guard let finalIndex = feedItems.firstIndex(where: { Self.itemContainsAsset($0, assetID: assetID) }) else {
                // #region agent log
                Diagnostics.debugBridge(hypothesisId: "D", location: "TikTokFeedViewModel.loadWindowContaining", message: "target NOT in built items", data: ["assetID": assetID, "feedItemsCount": feedItems.count, "mixedAssetsCount": mixedAssets.count])
                // #endregion
                Diagnostics.log("BridgeWindow: target not in built items, falling back")
                loadWindow(around: asset.creationDate ?? Date(), targetAssetID: assetID)
                return
            }
            // #region agent log
            Diagnostics.debugBridge(hypothesisId: "E", location: "TikTokFeedViewModel.loadWindowContaining", message: "bridge SUCCESS", data: ["assetID": assetID, "finalIndex": finalIndex, "feedItemsCount": feedItems.count])
            // #endregion
            items = feedItems
            initialIndexInWindow = finalIndex
            isLoading = false
            exploreModeActive = false
            isBridgeWindowActive = true
            segmentEndIndices.removeAll()
            Diagnostics.log("BridgeWindow: published \(feedItems.count) items, targetIndex=\(finalIndex)")
            let videosToPrefetch: [PHAsset] = feedItems.suffix(from: max(0, finalIndex - 2)).prefix(5).compactMap { item in
                if case .video(let a) = item.kind { return a }
                return nil
            }
            if !videosToPrefetch.isEmpty {
                VideoPrefetcher.shared.prefetch(videosToPrefetch)
                PlayerItemPrefetcher.shared.prefetch(videosToPrefetch)
            }
            if let first = feedItems.first {
                switch first.kind {
                case .video(let a):
                    FirstLaunchProbe.shared.windowPublished(items: feedItems.count, firstID: a.localIdentifier)
                case .photoCarousel(let arr):
                    FirstLaunchProbe.shared.windowPublished(items: feedItems.count, firstID: arr.first?.localIdentifier ?? "n/a")
                }
            }
        }
    }

    private static func itemContainsAsset(_ item: FeedItem, assetID: String) -> Bool {
        switch item.kind {
        case .video(let a): return a.localIdentifier == assetID
        case .photoCarousel(let arr): return arr.contains { $0.localIdentifier == assetID }
        }
    }

    /// Converts a flat mixed [PHAsset] list to [FeedItem]: videos as .video, photos as single-photo carousels.
    private func buildFeedItemsFromMixedAssets(_ assets: [PHAsset]) -> [FeedItem] {
        let hidden = DeletedVideosStore.snapshot()
        var out: [FeedItem] = []
        for a in assets {
            switch a.mediaType {
            case .video:
                if !hidden.contains(a.localIdentifier) {
                    out.append(.video(a))
                }
            case .image:
                out.append(.carousel([a]))
            default:
                break
            }
        }
        return out
    }

    func loadMoreIfNeeded(currentIndex: Int) {
        Diagnostics.log("LoadMore: currentIndex=\(currentIndex) items=\(items.count) cursor=\(videoCursor) explore=\(exploreModeActive) bridge=\(isBridgeWindowActive)")
        if isBridgeWindowActive { return }
        if exploreModeActive {
            guard let lastEnd = segmentEndIndices.last else { return }
            // EARLY PREWARM: start warming next day earlier to overlap network
            if currentIndex >= max(0, lastEnd - (prefetchThreshold * 2)) {
                _ = prewarmNextDayIfNeeded(biased: true)
            }
            // APPEND when close to end; prefer prewarmed day if available
            if currentIndex >= max(0, lastEnd - prefetchThreshold) {
                var appended = false
                if let next = prewarmedNextDayIndex {
                    appended = appendDay(dayIndex: next, asInitial: false)
                }
                if !appended {
                    var attempts = min(8, max(1, dayRanges.count - exploredDayIndices.count))
                    while attempts > 0 && !appended {
                        attempts -= 1
                        let nextDay = pickBiasedNextDayIndex() ?? pickNextRandomDayIndex()
                        if let nextDay {
                            appended = appendDay(dayIndex: nextDay, asInitial: false)
                        } else {
                            break
                        }
                    }
                }
                // After appending, attempt to prewarm the following day again
                if appended {
                    _ = prewarmNextDayIfNeeded(biased: true)
                }
            }
            return
        }

        // Legacy chronological paging (Start mode)
        guard let vResult = fetchVideos,
              items.indices.contains(currentIndex),
              currentIndex >= items.count - prefetchThreshold else { return }

        let vCount = vResult.count
        guard videoCursor < vCount else { return }
        
        let nextVEnd = min(vCount, videoCursor + pageSizeVideos)
        let vSliceBase = vResult.objects(at: IndexSet(integersIn: videoCursor..<nextVEnd))
        let vSlice = filterHidden(vSliceBase)
        
        let pSlice = photosAround(for: vSlice, limit: pageSizePhotos)
        let carousels = makeCarousels(from: pSlice)
        
        let (appended, _, videosTailCount) = interleave(videos: vSlice, carousels: carousels, startVideoStride: videosSinceLastCarousel)
        items.append(contentsOf: appended)
        Diagnostics.log("LoadMore: appended=\(appended.count) totalItems=\(items.count)")
        
        markPhotosUsed(from: appended)
        videosSinceLastCarousel = videosTailCount
        Diagnostics.log("StartWindow: appended videos=[\(videoCursor)..<\(nextVEnd)] carouselsAdded=\(carousels.count) totalItems=\(items.count)")
        videoCursor = nextVEnd
    }
    
    func configureAudioSession(active: Bool) {
        if active {
            Task { @MainActor in
                let ok = await PhaseGate.shared.waitUntil(.appActive, timeout: 5)
                Diagnostics.log("AudioSession gate appActive ok=\(ok) requestActive=\(active)")
                guard UIApplication.shared.applicationState == .active else {
                    Diagnostics.log("AudioSession: app not active, skip setActive(true)")
                    return
                }
                #if DEBUG
                DebugServiceGuards.assertPhaseGate(.avAudioSession, policy: .onActiveIdle)
                #endif
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                    try session.setActive(true, options: [])
                    Diagnostics.log("AudioSession: set active=true category=\(session.category.rawValue) mode=\(session.mode.rawValue) route=\(session.currentRoute.outputs.first?.portType.rawValue ?? "nil")")
                } catch {
                    Diagnostics.log("AudioSession: error active=true \(String(describing: error))")
                }
            }
        } else {
            Task { @MainActor in
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setActive(false, options: [])
                    Diagnostics.log("AudioSession: set active=false")
                } catch {
                    Diagnostics.log("AudioSession: error active=false \(String(describing: error))")
                }
            }
        }
    }

    private func handleDeletedVideosChanged() {
        guard !items.isEmpty else { return }
        let hidden = DeletedVideosStore.snapshot()
        let before = items.count
        items.removeAll { item in
            if case .video(let a) = item.kind {
                return hidden.contains(a.localIdentifier)
            }
            return false
        }
        if items.count != before {
            Diagnostics.log("Feed pruned hidden videos count=\(before - items.count)")
        }
    }
    
    private func makeCarousels(from photos: [PHAsset]) -> [[PHAsset]] {
        if !FeatureFlags.enablePhotoPosts { return [] }
        guard !photos.isEmpty else { return [] }
        var res: [[PHAsset]] = []
        var i = 0
        while i < photos.count {
            let n = min(Int.random(in: carouselMin...carouselMax), photos.count - i)
            let group = Array(photos[i..<(i + n)])
            res.append(group)
            i += n
        }
        return res
    }
    
    private func interleave(videos: [PHAsset], carousels: [[PHAsset]], startVideoStride: Int) -> (items: [FeedItem], usedPhotos: Int, videosTailCount: Int) {
        var out: [FeedItem] = []
        var usedPhotos = 0
        var cIdx = 0
        var stride = startVideoStride
        
        for v in videos {
            out.append(.video(v))
            stride += 1
            if FeatureFlags.enablePhotoPosts, stride >= interleaveEvery, cIdx < carousels.count {
                let c = carousels[cIdx]
                out.append(.carousel(c))
                usedPhotos += c.count
                cIdx += 1
                stride = 0
            }
        }
        return (out, usedPhotos, stride)
    }
    
    private func photosAround(for videos: [PHAsset], limit: Int) -> [PHAsset] {
        if !FeatureFlags.enablePhotoPosts { return [] }
        let dates = videos.compactMap(\.creationDate)
        guard let minVideoDate = dates.min(), let maxVideoDate = dates.max() else {
            Diagnostics.log("PhotosAround: no video creation dates, skipping")
            return []
        }
        let first = photosBetween(minDate: minVideoDate, maxDate: maxVideoDate, limit: limit, toleranceDays: 7)
        if !first.isEmpty { return first }
        let widened = photosBetween(minDate: minVideoDate, maxDate: maxVideoDate, limit: limit, toleranceDays: 30)
        return widened
    }
    
    private func photosBetween(minDate: Date, maxDate: Date, limit: Int, toleranceDays: Int) -> [PHAsset] {
        if !FeatureFlags.enablePhotoPosts { return [] }
        let tol: TimeInterval = Double(toleranceDays) * 24 * 60 * 60
        let lower = minDate.addingTimeInterval(-tol)
        let upper = maxDate.addingTimeInterval(tol)
        
        let opts = PHFetchOptions()
        let screenshotMask = PHAssetMediaSubtype.photoScreenshot.rawValue
        opts.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@ AND ((mediaSubtypes & %d) == 0)",
            PHAssetMediaType.image.rawValue, lower as NSDate, upper as NSDate, screenshotMask
        )
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: opts)
        let count = Swift.min(limit, result.count)
        guard count > 0 else {
            Diagnostics.log("PhotosBetween: 0 results tolDays=\(toleranceDays) range=[\(lower) .. \(upper)]")
            return []
        }
        let slice = result.objects(at: IndexSet(integersIn: 0..<count))
        let filtered = slice.filter {
            !usedPhotoIDs.contains($0.localIdentifier) && !$0.mediaSubtypes.contains(.photoScreenshot)
        }
        Diagnostics.log("PhotosBetween: fetched=\(slice.count) filteredUnique=\(filtered.count) tolDays=\(toleranceDays)")
        return filtered
    }
    
    private func markPhotosUsed(from feedItems: [FeedItem]) {
        if !FeatureFlags.enablePhotoPosts { return }
        for item in feedItems {
            if case .photoCarousel(let arr) = item.kind {
                for a in arr {
                    usedPhotoIDs.insert(a.localIdentifier)
                }
            }
        }
    }

    /// Find feed index containing the given asset (for shared position with Carousel).
    func indexOfAsset(id: String) -> Int? {
        indexOfAssetInItems(id, items: items)
    }

    private func indexOfAssetInItems(_ id: String, items: [FeedItem]) -> Int? {
        for (idx, item) in items.enumerated() {
            switch item.kind {
            case .video(let a):
                if a.localIdentifier == id { return idx }
            case .photoCarousel(let arr):
                if arr.contains(where: { $0.localIdentifier == id }) { return idx }
            }
        }
        return nil
    }
}