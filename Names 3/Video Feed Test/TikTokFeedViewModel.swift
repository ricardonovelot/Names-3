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

    /// When true, we loaded via bridge (loadWindowContaining); load more via loadMoreForBridgeMode when near end.
    private var isBridgeWindowActive = false
    private var bridgeLoadMoreInFlight = false

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
            Task { @MainActor in self?.handleDeletedVideosChanged() }
        }
        if feedSettingsObserver == nil {
            feedSettingsObserver = NotificationCenter.default.addObserver(forName: .feedSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
        }
    }

    private var feedSettingsObserver: NSObjectProtocol?

    deinit {
        NotificationCenter.default.removeObserver(self, name: .deletedVideosChanged, object: nil)
        feedSettingsObserver.map { NotificationCenter.default.removeObserver($0) }
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
        // Preserve position when reloading due to settings (e.g. Exclude screenshots)
        if let id = FeedPositionStore.savedAssetID {
            loadWindowContaining(assetID: id)
        } else {
            loadWindow()
        }
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

    /// Uses bridge target if set (Carousel→Feed or saved position from parent); otherwise normal load.
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

    /// Uses recency-biased algorithm to pick the next day.
    private func pickNextDayIndex() -> Int? {
        guard !dayRanges.isEmpty else { return nil }
        let dayInfos = dayRanges.enumerated().map { idx, r in
            FeedDaySelectionContext.DayInfo(dayIndex: idx, dayStart: r.dayStart, start: r.start, end: r.end)
        }
        let ctx = FeedDaySelectionContext(
            dayInfos: dayInfos,
            exploredDayIndices: exploredDayIndices,
            lastAppendedDayIndex: lastAppendedDayIndex,
            fetchVideos: fetchVideos,
            now: Date()
        )
        let chosen = FeedNextDayAlgorithm.pickNextDay(context: ctx)
        if let c = chosen {
            let mode = ctx.exploredDaysCount >= FeedExploreSettings.recentDaysThreshold
                ? FeedExploreSettings.exploreMode.rawValue
                : "recent"
            Diagnostics.log("ExploreAlgo: \(mode) dayIdx=\(c) of \(dayRanges.count) explored=\(ctx.exploredDaysCount)")
        }
        return chosen
    }

    // Prewarm the next day early by prefetching the first few videos from that day.
    @discardableResult
    private func prewarmNextDayIfNeeded(biased: Bool = true) -> Int? {
        guard exploreModeActive, !prewarmInFlight, prewarmedNextDayIndex == nil else { return prewarmedNextDayIndex }
        guard let dayIdx = pickNextDayIndex() else { return nil }
        guard let vResult = fetchVideos, dayRanges.indices.contains(dayIdx) else { return nil }
        let r = dayRanges[dayIdx]
        let baseSlice = vResult.objects(at: IndexSet(integersIn: r.start..<r.end))
        let vSlice = filterHidden(baseSlice)
        guard !vSlice.isEmpty else {
            exploredDayIndices.insert(dayIdx)
            return nil
        }
        let capped = FeedVideoHourCap.capOnePerHour(vSlice)
        let prewarmCount = min(8, capped.count)
        let warm = Array(capped.prefix(prewarmCount))
        prewarmInFlight = true
        prewarmedNextDayIndex = dayIdx
        Diagnostics.log("ExplorePrewarm: start dayIdx=\(dayIdx) date=\(r.dayStart) warmCount=\(warm.count)")
        VideoPrefetcher.shared.prefetch(warm)
        PlayerItemPrefetcher.shared.prefetch(warm)
        // Note: we don't block; warming continues while user scrolls.
        return dayIdx
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
        let capped = FeedVideoHourCap.capOnePerHour(vSlice)

        let pSlice = photosAround(for: capped, limit: pageSizePhotos)
        let carousels = makeCarousels(from: pSlice)

        let startStride = videosSinceLastCarousel
        let (built, _, newTailCount) = interleave(videos: capped, carousels: carousels, startVideoStride: startStride)

        if asInitial {
            items = built
            logItemsStructure(built, source: "ExploreDay")
            initialIndexInWindow = 0
            isLoading = false
            Diagnostics.log("ExploreDay: initial publish items=\(items.count) day=\(r.dayStart) videos=\(capped.count) carousels=\(carousels.count)")
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
            let prewarmCount = min(6, capped.count)
            if prewarmCount > 1 {
                let extra = Array(capped.prefix(prewarmCount).dropFirst())
                VideoPrefetcher.shared.prefetch(extra)
                PlayerItemPrefetcher.shared.prefetch(extra)
            }
        } else {
            let before = items.count
            items.append(contentsOf: built)
            Diagnostics.log("ExploreDay: appended segment items+\(built.count) total=\(items.count) day=\(r.dayStart) videos=\(capped.count) carousels=\(carousels.count)")
            let appendedCount = items.count - before
            if appendedCount <= 0 {
                return false
            }
            // proactively prefetch the first N videos of the newly appended day
            let prewarmCount = min(8, capped.count)
            if prewarmCount > 0 {
                let warm = Array(capped.prefix(prewarmCount))
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
        let capped = FeedVideoHourCap.capOnePerHour(vSlice)

        let pSlice = photosAround(for: capped, limit: pageSizePhotos)
        let carousels = makeCarousels(from: pSlice)
        let (itemsBuilt, _, videosTailCount) = interleave(videos: capped, carousels: carousels, startVideoStride: 0)

        items = itemsBuilt
        logItemsStructure(itemsBuilt, source: "StartWindow")
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
        Diagnostics.log("StartWindow: videosTotal=\(vResult.count) vWindow=\(capped.count) carousels=\(carousels.count) first=\(firstID)")
    }
    
    func loadRandomWindow() {
        isLoading = true
        Diagnostics.log("Explore: begin (recent-first like ahead-of-time)")
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

        // First items: recent content with variety — cap per day so we don't see 50 from one event.
        let (vSlice, cursorEnd, usedRange) = buildVariedRecentSlice()

        guard !vSlice.isEmpty else {
            // All recent videos hidden; fallback to most recent window (not random)
            Diagnostics.log("Explore: all recent hidden, fallback to most recent window")
            let vCount = vResult.count
            let windowSize = min(pageSizeVideos, vCount)
            let start = max(0, vCount - windowSize)
            let end = vCount
            let fallbackSlice = filterHidden(vResult.objects(at: IndexSet(integersIn: start..<end)))
            if !fallbackSlice.isEmpty {
                publishInitialWindow(videos: fallbackSlice, source: "ExploreFallback", cursorEnd: end)
                markDaysExploredForIndices(start..<end)
                lastAppendedDayIndex = dayIndexForFetchIndex(end - 1)
            } else {
                items = []
                initialIndexInWindow = nil
            }
            isLoading = false
            return
        }

        publishInitialWindow(videos: vSlice, source: "ExploreRecentFirst", cursorEnd: cursorEnd)
        markDaysExploredForIndices(usedRange)
        lastAppendedDayIndex = dayIndexForFetchIndex(cursorEnd - 1)
        _ = prewarmNextDayIfNeeded(biased: true)
        isLoading = false
    }

    /// Builds initial video slice with variety using heuristics (uniform, momentCluster, richDay).
    private func buildVariedRecentSlice() -> (videos: [PHAsset], cursorEnd: Int, usedRange: Range<Int>) {
        guard let vResult = fetchVideos, !dayRanges.isEmpty else {
            return ([], 0, 0..<0)
        }
        let mode = FeedInitialVarietySettings.mode
        var collected: [PHAsset] = []
        var lastDayEndUsed = 0
        for dayIdx in 0..<dayRanges.count {
            guard collected.count < pageSizeVideos else { break }
            let r = dayRanges[dayIdx]
            let baseSlice = vResult.objects(at: IndexSet(integersIn: r.start..<r.end))
            let filtered = filterHidden(baseSlice)
            let maxRemaining = pageSizeVideos - collected.count
            guard maxRemaining > 0, !filtered.isEmpty else { continue }
            let sampled = FeedInitialVarietySampler.sample(filtered, mode: mode, maxTotal: maxRemaining)
            guard !sampled.isEmpty else { continue }
            collected.append(contentsOf: sampled)
            lastDayEndUsed = r.end
        }
        let cursorEnd = lastDayEndUsed
        let usedRange = 0..<cursorEnd
        return (collected, cursorEnd, usedRange)
    }

    /// Publishes initial feed items from a video slice and sets cursor/segment state.
    private func publishInitialWindow(videos: [PHAsset], source: String, cursorEnd: Int) {
        let capped = FeedVideoHourCap.capOnePerHour(videos)
        let pSlice = photosAround(for: capped, limit: pageSizePhotos)
        let carousels = makeCarousels(from: pSlice)
        let (itemsBuilt, _, videosTailCount) = interleave(videos: capped, carousels: carousels, startVideoStride: 0)

        items = itemsBuilt
        logItemsStructure(itemsBuilt, source: source)
        Diagnostics.log("\(source): publish items=\(items.count)")
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

        videoCursor = cursorEnd
        videosSinceLastCarousel = videosTailCount
        markPhotosUsed(from: itemsBuilt)
        segmentEndIndices.append(items.count - 1)
    }

    /// Marks day ranges that overlap the given fetch indices as explored.
    private func markDaysExploredForIndices(_ range: Range<Int>) {
        for (dayIdx, r) in dayRanges.enumerated() {
            if r.start < range.upperBound && r.end > range.lowerBound {
                exploredDayIndices.insert(dayIdx)
            }
        }
    }

    /// Returns the day index containing the given fetch result index.
    private func dayIndexForFetchIndex(_ fetchIndex: Int) -> Int? {
        for (dayIdx, r) in dayRanges.enumerated() {
            if fetchIndex >= r.start && fetchIndex < r.end {
                return dayIdx
            }
        }
        return dayRanges.isEmpty ? nil : dayRanges.count - 1
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
        let capped = FeedVideoHourCap.capOnePerHour(vSlice)
        let pSlice = photosAround(for: capped, limit: pageSizePhotos)
        let carousels = makeCarousels(from: pSlice)
        let (itemsBuilt, _, videosTailCount) = interleave(videos: capped, carousels: carousels, startVideoStride: 0)

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
        logItemsStructure(itemsBuilt, source: "DateWindow")
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
            let (mixedAssets, _) = await NameFacesCarouselAssetFetcher.fetchMixedAssetsAround(
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
            logItemsStructure(feedItems, source: "BridgeWindow")
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

    /// Injects assets from Carousel when switching Carousel→Feed. No fetch—uses exact same assets.
    func injectItemsFromCarousel(_ assets: [PHAsset], scrollToAssetID: String?) {
        guard !assets.isEmpty else { return }
        let feedItems = buildFeedItemsFromMixedAssets(assets)
        guard !feedItems.isEmpty else { return }
        items = feedItems
        logItemsStructure(feedItems, source: "BridgeInject")
        isBridgeWindowActive = true
        exploreModeActive = false
        segmentEndIndices.removeAll()
        if let id = scrollToAssetID, let idx = feedItems.firstIndex(where: { Self.itemContainsAsset($0, assetID: id) }) {
            initialIndexInWindow = idx
        } else {
            initialIndexInWindow = 0
        }
        isLoading = false
        Diagnostics.log("BridgeInject: Carousel→Feed \(feedItems.count) items, scrollTo=\(scrollToAssetID ?? "nil")")
    }

    /// Logs item structure for scroll debugging. Call when items are published.
    private func logItemsStructure(_ items: [FeedItem], source: String) {
        let mode = FeedPhotoGroupingMode.current.rawValue
        let pattern = items.prefix(12).map { item -> String in
            switch item.kind {
            case .video: return "V"
            case .photoCarousel: return "C"
            }
        }.joined()
        let videoCount = items.filter { if case .video = $0.kind { return true }; return false }.count
        let carouselCount = items.filter { if case .photoCarousel = $0.kind { return true }; return false }.count
        if DiagnosticsConfig.shared.verbosity != .off {
            print("[PhotoGroupingScroll] Items published: source=\(source) mode=\(mode) count=\(items.count) V=\(videoCount) C=\(carouselCount) pattern=\(pattern)")
        }
    }

    /// Converts a flat mixed [PHAsset] list to [FeedItem] using FeedPhotoGroupingMode.
    private func buildFeedItemsFromMixedAssets(_ assets: [PHAsset]) -> [FeedItem] {
        let hidden = DeletedVideosStore.snapshot()
        let mode = FeedPhotoGroupingMode.current
        switch mode {
        case .off:
            return buildFeedItemsMixedOff(assets, hidden: hidden)
        case .betweenVideo:
            return buildFeedItemsMixedBetweenVideo(assets, hidden: hidden)
        case .byDay:
            return buildFeedItemsMixedByDay(assets, hidden: hidden)
        case .byCount:
            return buildFeedItemsMixedByCount(assets, hidden: hidden)
        }
    }

    private func buildFeedItemsMixedOff(_ assets: [PHAsset], hidden: Set<String>) -> [FeedItem] {
        var out: [FeedItem] = []
        for a in assets {
            if a.mediaType == .video, !hidden.contains(a.localIdentifier) {
                out.append(.video(a))
            }
        }
        return out
    }

    private func buildFeedItemsMixedBetweenVideo(_ assets: [PHAsset], hidden: Set<String>) -> [FeedItem] {
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

    private func buildFeedItemsMixedByDay(_ assets: [PHAsset], hidden: Set<String>) -> [FeedItem] {
        let cal = Calendar.current
        var out: [FeedItem] = []
        var photoBuffer: [PHAsset] = []
        var lastPhotoDayStart: Date?
        for a in assets {
            switch a.mediaType {
            case .video:
                if !hidden.contains(a.localIdentifier) {
                    if !photoBuffer.isEmpty {
                        out.append(.carousel(photoBuffer))
                        photoBuffer = []
                        lastPhotoDayStart = nil
                    }
                    out.append(.video(a))
                }
            case .image:
                let dayStart = a.creationDate.map { cal.startOfDay(for: $0) }
                if let last = lastPhotoDayStart, let d = dayStart, d != last {
                    if !photoBuffer.isEmpty {
                        out.append(.carousel(photoBuffer))
                        photoBuffer = []
                    }
                }
                lastPhotoDayStart = dayStart
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

    private func buildFeedItemsMixedByCount(_ assets: [PHAsset], hidden: Set<String>) -> [FeedItem] {
        let batchSize = 5
        var out: [FeedItem] = []
        var photoBuffer: [PHAsset] = []
        for a in assets {
            switch a.mediaType {
            case .video:
                if !hidden.contains(a.localIdentifier) {
                    if !photoBuffer.isEmpty {
                        for i in stride(from: 0, to: photoBuffer.count, by: batchSize) {
                            let end = min(i + batchSize, photoBuffer.count)
                            out.append(.carousel(Array(photoBuffer[i..<end])))
                        }
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
            for i in stride(from: 0, to: photoBuffer.count, by: batchSize) {
                let end = min(i + batchSize, photoBuffer.count)
                out.append(.carousel(Array(photoBuffer[i..<end])))
            }
        }
        return out
    }

    func loadMoreIfNeeded(currentIndex: Int) {
        Diagnostics.log("LoadMore: currentIndex=\(currentIndex) items=\(items.count) cursor=\(videoCursor) explore=\(exploreModeActive) bridge=\(isBridgeWindowActive)")
        if isBridgeWindowActive {
            if currentIndex >= items.count - prefetchThreshold {
                loadMoreForBridgeMode()
            }
            return
        }
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
                        let nextDay = pickNextDayIndex()
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
        let capped = FeedVideoHourCap.capOnePerHour(vSlice)

        let pSlice = photosAround(for: capped, limit: pageSizePhotos)
        let carousels = makeCarousels(from: pSlice)

        let (appended, _, videosTailCount) = interleave(videos: capped, carousels: carousels, startVideoStride: videosSinceLastCarousel)
        items.append(contentsOf: appended)
        Diagnostics.log("LoadMore: appended=\(appended.count) totalItems=\(items.count)")
        
        markPhotosUsed(from: appended)
        videosSinceLastCarousel = videosTailCount
        Diagnostics.log("StartWindow: appended videos=[\(videoCursor)..<\(nextVEnd)] carouselsAdded=\(carousels.count) totalItems=\(items.count)")
        videoCursor = nextVEnd
    }

    /// Load more mixed assets when in bridge mode and near the end.
    private func loadMoreForBridgeMode() {
        guard !bridgeLoadMoreInFlight, !items.isEmpty else { return }
        let oldestDate = items.flatMap { item -> [Date] in
            switch item.kind {
            case .video(let a): return (a.creationDate).map { [$0] } ?? []
            case .photoCarousel(let arr): return arr.compactMap(\.creationDate)
            }
        }.min()
        guard let date = oldestDate else { return }
        bridgeLoadMoreInFlight = true
        Task { @MainActor in
            defer { bridgeLoadMoreInFlight = false }
            let moreAssets = await NameFacesCarouselAssetFetcher.fetchAssetsOlderThan(date, limit: 60)
            guard !moreAssets.isEmpty else {
                Diagnostics.log("BridgeLoadMore: no older assets")
                return
            }
            let existingIDs = Set(FeedItem.flattenToAssets(items).map(\.localIdentifier))
            let newAssets = moreAssets.filter { !existingIDs.contains($0.localIdentifier) }
            guard !newAssets.isEmpty else {
                Diagnostics.log("BridgeLoadMore: all \(moreAssets.count) already in feed")
                return
            }
            let newItems = buildFeedItemsFromMixedAssets(newAssets)
            guard !newItems.isEmpty else { return }
            items.append(contentsOf: newItems)
            Diagnostics.log("BridgeLoadMore: appended \(newItems.count) items, total=\(items.count)")
        }
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
                    try session.setActive(false, options: [.notifyOthersOnDeactivation])
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
        switch FeedPhotoGroupingMode.current {
        case .off:
            return []
        case .betweenVideo, .byCount:
            if !FeatureFlags.enablePhotoPosts { return [] }
            return makeCarouselsByMoment(from: photos)
        case .byDay:
            if !FeatureFlags.enablePhotoPosts { return [] }
            return makeCarouselsByDay(from: photos)
        }
    }

    /// Groups by time gap (moment), applies sampling (uniform or density-adaptive) when configured.
    private func makeCarouselsByMoment(from photos: [PHAsset]) -> [[PHAsset]] {
        guard !photos.isEmpty else { return [] }
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

    private func makeCarouselsByDay(from photos: [PHAsset]) -> [[PHAsset]] {
        guard !photos.isEmpty else { return [] }
        let cal = Calendar.current
        var res: [[PHAsset]] = []
        var current: [PHAsset] = []
        var lastDayStart: Date?
        for a in photos {
            let dayStart = a.creationDate.map { cal.startOfDay(for: $0) }
            if let last = lastDayStart, let d = dayStart, d != last, !current.isEmpty {
                let sampled = CarouselSampling.sample(current, mode: CarouselSamplingSettings.mode)
                if sampled.count >= 2 { res.append(sampled) }
                current = []
            }
            lastDayStart = dayStart
            current.append(a)
        }
        if !current.isEmpty {
            let sampled = CarouselSampling.sample(current, mode: CarouselSamplingSettings.mode)
            if sampled.count >= 2 { res.append(sampled) }
        }
        return res
    }
    
    private func interleave(videos: [PHAsset], carousels: [[PHAsset]], startVideoStride: Int) -> (items: [FeedItem], usedPhotos: Int, videosTailCount: Int) {
        switch FeedPhotoGroupingMode.current {
        case .off:
            return (videos.map { .video($0) }, 0, videos.count)
        case .betweenVideo:
            return interleaveBetweenVideo(videos: videos, carousels: carousels)
        case .byDay, .byCount:
            return interleaveByStride(videos: videos, carousels: carousels, startVideoStride: startVideoStride)
        }
    }

    private func interleaveBetweenVideo(videos: [PHAsset], carousels: [[PHAsset]]) -> (items: [FeedItem], usedPhotos: Int, videosTailCount: Int) {
        var out: [FeedItem] = []
        var usedPhotos = 0
        var cIdx = 0
        for v in videos {
            out.append(.video(v))
            if cIdx < carousels.count {
                while cIdx < carousels.count && !FeedDataHelpers.isCarouselAlignedWithVideo(carousels[cIdx], video: v) {
                    cIdx += 1
                }
                if cIdx < carousels.count {
                    let c = carousels[cIdx]
                    out.append(.carousel(c))
                    usedPhotos += c.count
                    cIdx += 1
                }
            }
        }
        return (out, usedPhotos, 0)
    }

    private func interleaveByStride(videos: [PHAsset], carousels: [[PHAsset]], startVideoStride: Int) -> (items: [FeedItem], usedPhotos: Int, videosTailCount: Int) {
        var out: [FeedItem] = []
        var usedPhotos = 0
        var cIdx = 0
        var stride = startVideoStride
        for v in videos {
            out.append(.video(v))
            stride += 1
            if FeatureFlags.enablePhotoPosts, stride >= interleaveEvery, cIdx < carousels.count {
                while cIdx < carousels.count && !FeedDataHelpers.isCarouselAlignedWithVideo(carousels[cIdx], video: v) {
                    cIdx += 1
                }
                if cIdx < carousels.count {
                    let c = carousels[cIdx]
                    out.append(.carousel(c))
                    usedPhotos += c.count
                    cIdx += 1
                    stride = 0
                }
            }
        }
        return (out, usedPhotos, stride)
    }
    
    private func photosAround(for videos: [PHAsset], limit: Int) -> [PHAsset] {
        if FeedPhotoGroupingMode.current == .off { return [] }
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
        opts.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
            PHAssetMediaType.image.rawValue, lower as NSDate, upper as NSDate
        )
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: opts)
        guard result.count > 0 else {
            Diagnostics.log("PhotosBetween: 0 results tolDays=\(toleranceDays) range=[\(lower) .. \(upper)]")
            return []
        }
        let excludeScreenshots = ExcludeScreenshotsPreference.excludeScreenshots
        var assets: [PHAsset] = []
        assets.reserveCapacity(limit)
        result.enumerateObjects { asset, _, stop in
            guard assets.count < limit else { stop.pointee = true; return }
            if self.usedPhotoIDs.contains(asset.localIdentifier) { return }
            if excludeScreenshots && ExcludeScreenshotsPreference.isLikelyRealScreenshot(asset) { return }
            assets.append(asset)
        }
        let resultSlice = assets
        Diagnostics.log("PhotosBetween: fetched=\(result.count) kept=\(resultSlice.count) tolDays=\(toleranceDays)")
        return resultSlice
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