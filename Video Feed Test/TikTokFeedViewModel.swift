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
    
    init(mode: FeedMode) {
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
        
        guard status != .notDetermined else {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                Task { @MainActor [weak self] in
                    self?.authorization = newStatus
                    if newStatus == .authorized || newStatus == .limited {
                        self?.loadWindow()
                    }
                }
            }
            return
        }
        
        if status == .authorized || status == .limited {
            loadWindow()
        }
    }
    
    func reload() {
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

    private func filterHidden(_ videos: [PHAsset]) -> [PHAsset] {
        let hidden = DeletedVideosStore.snapshot()
        if hidden.isEmpty { return videos }
        return videos.filter { !hidden.contains($0.localIdentifier) }
    }
    
    private func commonFetchSetup() {
        let videoOpts = PHFetchOptions()
        videoOpts.predicate = NSPredicate(format: "mediaType == %d AND duration >= 1.0", PHAssetMediaType.video.rawValue)
        videoOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchVideos = PHAsset.fetchAssets(with: videoOpts)
        
        videoCursor = 0
        videosSinceLastCarousel = 0
        usedPhotoIDs.removeAll()
    }
    
    private func loadStartWindow() {
        isLoading = true
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
        commonFetchSetup()
        guard let vResult = fetchVideos, vResult.count > 0 else {
            items = []
            isLoading = false
            initialIndexInWindow = nil
            Diagnostics.log("RandomWindow: no video assets")
            return
        }
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
        Diagnostics.log("RandomWindow: totalVideos=\(vCount) window=[\(start)..<\(end)] first id=\(chosenID) carousels=\(carousels.count)")
    }

    func loadWindow(around targetDate: Date) {
        isLoading = true
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

        let clampedIndex = min(max(foundIndex, start), end - 1)
        let selectedID = vResult.object(at: clampedIndex).localIdentifier
        let initialLocalIndex: Int = {
            for (idx, it) in itemsBuilt.enumerated() {
                if case .video(let a) = it.kind, a.localIdentifier == selectedID {
                    return idx
                }
            }
            return 0
        }()

        items = itemsBuilt
        initialIndexInWindow = initialLocalIndex
        isLoading = false

        videoCursor = end
        videosSinceLastCarousel = videosTailCount
        markPhotosUsed(from: itemsBuilt)

        Diagnostics.log("DateWindow: target=\(targetDate) window=[\(start)..<\(end)] initialLocalIndex=\(initialLocalIndex)")
    }

    func jumpToOneYearAgo() {
        if let date = Calendar.current.date(byAdding: .year, value: -1, to: Date()) {
            loadWindow(around: date)
        } else {
            loadRandomWindow()
        }
    }

    func loadMoreIfNeeded(currentIndex: Int) {
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
        
        markPhotosUsed(from: appended)
        videosSinceLastCarousel = videosTailCount
        Diagnostics.log("StartWindow: appended videos=[\(videoCursor)..<\(nextVEnd)] carouselsAdded=\(carousels.count) totalItems=\(items.count)")
        videoCursor = nextVEnd
    }
    
    func configureAudioSession(active: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(active, options: [])
        } catch {
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
}