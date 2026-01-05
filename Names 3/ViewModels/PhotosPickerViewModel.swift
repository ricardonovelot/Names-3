import SwiftUI
import Photos
import Combine

// MARK: - Photos Picker State

enum PhotosPickerState: Equatable {
    case idle
    case requestingAuthorization
    case loading
    case loaded
    case error(PhotosPickerError)
    case empty
}

// MARK: - Photos Picker Error

enum PhotosPickerError: LocalizedError, Equatable {
    case authorizationDenied
    case authorizationRestricted
    case loadingFailed
    case noPhotosFound
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Photos access denied"
        case .authorizationRestricted:
            return "Photos access restricted"
        case .loadingFailed:
            return "Failed to load photos"
        case .noPhotosFound:
            return "No photos found"
        }
    }
}

// MARK: - Photos Picker ViewModel

@MainActor
final class PhotosPickerViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var state: PhotosPickerState = .idle
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published private(set) var assets: [PHAsset] = []
    
    // MARK: - Dependencies
    
    private let photoService: PhotoLibraryServiceProtocol
    private let deduplicationService: DeduplicationService
    
    // MARK: - Private Properties
    
    private var scope: PhotosPickerScope
    private var changeObserver: PHPhotoLibraryChangeObserver?
    
    private var fetchResult: PHFetchResult<PHAsset>?
    private var loadedCount: Int = 0
    private let pageSize: Int = 200
    
    private var loadTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    
    private var reloadDebounceTask: Task<Void, Never>?
    private var isReloadingSuppressed = false
    
    private var initialScrollDate: Date?
    
    var isObserving: Bool {
        return changeObserver != nil
    }
    
    // MARK: - Initialization
    
    init(
        scope: PhotosPickerScope,
        initialScrollDate: Date? = nil,
        photoService: PhotoLibraryServiceProtocol = PhotoLibraryService.shared,
        deduplicationService: DeduplicationService = .shared
    ) {
        self.scope = scope
        self.initialScrollDate = initialScrollDate
        self.photoService = photoService
        self.deduplicationService = deduplicationService
    }
    
    deinit {
        print("🔵 [PhotosVM] Deinitializing")
        // Cleanup observer synchronously without MainActor isolation
        if let observer = changeObserver {
            photoService.unregisterObserver(observer)
        }
        // Cancel any pending tasks
        loadTask?.cancel()
        retryTask?.cancel()
        reloadDebounceTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    func requestAuthorizationIfNeeded() {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = currentStatus
        print("🔵 [PhotosVM] Current authorization status: \(currentStatus.rawValue)")
        
        if currentStatus == .notDetermined {
            state = .requestingAuthorization
            print("🔄 [PhotosVM] Requesting authorization")
            
            Task {
                let newStatus = try await photoService.requestAuthorization()
                authorizationStatus = newStatus
                print("✅ [PhotosVM] Authorization result: \(newStatus.rawValue)")
                
                switch newStatus {
                case .authorized, .limited:
                    await loadAssets()
                case .denied:
                    state = .error(.authorizationDenied)
                case .restricted:
                    state = .error(.authorizationRestricted)
                case .notDetermined:
                    state = .idle
                @unknown default:
                    state = .idle
                }
            }
        } else if currentStatus == .authorized || currentStatus == .limited {
            Task {
                await loadAssets()
            }
        } else if currentStatus == .denied {
            state = .error(.authorizationDenied)
        } else if currentStatus == .restricted {
            state = .error(.authorizationRestricted)
        }
    }
    
    func loadAssets() async {
        print("🔵 [PhotosVM] loadAssets started for scope: \(scope)")
        loadTask?.cancel()
        retryTask?.cancel()
        
        state = .loading
        assets = []
        fetchResult = nil
        loadedCount = 0
        
        loadTask = Task {
            switch scope {
            case .day(let date):
                await loadAssetsForDay(date)
            case .all:
                await loadAllAssetsWithPriority()
            }
        }
        
        await loadTask?.value
        print("✅ [PhotosVM] loadAssets completed - assets count: \(assets.count), state: \(state)")
    }
    
    func reloadForScope(_ newScope: PhotosPickerScope) {
        guard newScope != scope else { return }
        print("🔵 [PhotosVM] Reloading for new scope: \(newScope)")
        scope = newScope
        
        Task {
            await loadAssets()
        }
    }
    
    func handlePagination(for asset: PHAsset) {
        guard case .all = scope else { return }
        guard let fetch = fetchResult else { return }
        guard loadedCount < fetch.count else { return }
        
        if let index = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }),
           loadedCount - index <= 24 {
            print("🔄 [PhotosVM] Loading more assets - current: \(loadedCount), total: \(fetch.count)")
            Task {
                await loadMoreAssets()
            }
        }
    }
    
    func startObservingChanges() {
        guard changeObserver == nil else { return }
        
        print("🔵 [PhotosVM] Starting photo library change observation")
        changeObserver = photoService.observeChanges { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // Debounce reloads to prevent interrupting user interactions
                print("🔄 [PhotosVM] Photo library changed, scheduling debounced reload")
                
                // Cancel any pending reload
                self.reloadDebounceTask?.cancel()
                
                // Don't reload if suppressed
                guard !self.isReloadingSuppressed else {
                    print("⏸️ [PhotosVM] Reload suppressed during user interaction")
                    return
                }
                
                // Schedule reload after 2 seconds
                self.reloadDebounceTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    
                    guard !Task.isCancelled else { return }
                    guard !self.isReloadingSuppressed else { return }
                    
                    print("🔄 [PhotosVM] Executing debounced reload")
                    await self.loadAssets()
                }
            }
        }
    }
    
    func stopObservingChanges() {
        if let observer = changeObserver {
            print("🔵 [PhotosVM] Stopping photo library change observation")
            photoService.unregisterObserver(observer)
            changeObserver = nil
        }
    }
    
    func suppressReload(_ suppress: Bool) {
        isReloadingSuppressed = suppress
        print("🔵 [PhotosVM] Reload suppression: \(suppress)")
        
        // Cancel any pending debounced reload to avoid a post-dismiss update nuking the grid
        if suppress {
            reloadDebounceTask?.cancel()
            print("🔵 [PhotosVM] Cancelled pending debounced reload")
        }
    }
    
    // MARK: - Private Methods
    
    private func cleanup() {
        loadTask?.cancel()
        retryTask?.cancel()
        stopObservingChanges()
    }
    
    private func loadAssetsForDay(_ date: Date) async {
        print("🔵 [PhotosVM] Loading assets for day: \(date)")
        try? await Task.sleep(for: .milliseconds(120))
        
        guard !Task.isCancelled else {
            print("⚠️ [PhotosVM] Task cancelled during day load")
            return
        }
        
        let (start, end) = DateUtility.dayBounds(for: date)
        print("🔵 [PhotosVM] Date bounds - start: \(start), end: \(end)")
        var fetchedAssets = photoService.fetchAssets(from: start, to: end)
        print("🔵 [PhotosVM] Initial fetch: \(fetchedAssets.count) assets")
        
        if fetchedAssets.isEmpty {
            let calendar = Calendar.current
            let relaxedStart = calendar.date(byAdding: .hour, value: -12, to: start) ?? start
            let relaxedEnd = calendar.date(byAdding: .hour, value: 12, to: end) ?? end
            
            print("🔄 [PhotosVM] Trying relaxed bounds - start: \(relaxedStart), end: \(relaxedEnd)")
            let relaxedAssets = photoService.fetchAssets(from: relaxedStart, to: relaxedEnd)
            fetchedAssets = relaxedAssets.filter { asset in
                guard let creationDate = asset.creationDate else { return false }
                return creationDate >= start && creationDate < end
            }
            print("🔵 [PhotosVM] Relaxed fetch: \(fetchedAssets.count) assets")
        }
        
        guard !Task.isCancelled else {
            print("⚠️ [PhotosVM] Task cancelled after fetch")
            return
        }
        
        if fetchedAssets.isEmpty {
            assets = []
            state = .empty
            print("⚠️ [PhotosVM] No assets found, scheduling retry")
            scheduleRetry(for: date)
            return
        }
        
        print("🔄 [PhotosVM] Deduplicating \(fetchedAssets.count) assets")
        let deduplicated = await deduplicationService.deduplicateAssets(fetchedAssets)
        print("✅ [PhotosVM] Deduplicated to \(deduplicated.count) assets")
        
        guard !Task.isCancelled else {
            print("⚠️ [PhotosVM] Task cancelled after deduplication")
            return
        }
        
        assets = deduplicated
        state = deduplicated.isEmpty ? .empty : .loaded
        print("✅ [PhotosVM] Day loading complete - final count: \(assets.count)")
    }
    
    private func loadAllAssetsPaged() async {
        print("🔵 [PhotosVM] Loading all assets (paged)")
        let fetchResult = photoService.fetchAssets(for: .all)
        self.fetchResult = fetchResult
        print("🔵 [PhotosVM] Total assets available: \(fetchResult.count)")
        
        guard fetchResult.count > 0 else {
            state = .empty
            print("⚠️ [PhotosVM] No assets in library")
            return
        }
        
        await loadMoreAssets()
    }
    
    private func loadAllAssetsWithPriority() async {
        print("🔵 [PhotosVM] Loading all assets with priority date: \(initialScrollDate?.description ?? "none")")
        let fetchResult = photoService.fetchAssets(for: .all)
        self.fetchResult = fetchResult
        print("🔵 [PhotosVM] Total assets available: \(fetchResult.count)")
        
        guard fetchResult.count > 0 else {
            state = .empty
            print("⚠️ [PhotosVM] No assets in library")
            return
        }
        
        if let targetDate = initialScrollDate {
            await loadAssetsAroundDate(targetDate, fetchResult: fetchResult)
        } else {
            await loadMoreAssets()
        }
    }
    
    private func loadAssetsAroundDate(_ targetDate: Date, fetchResult: PHFetchResult<PHAsset>) async {
        print("🔵 [PhotosVM] Loading assets around target date: \(targetDate)")
        
        // Use binary search to find the closest asset to target date
        var left = 0
        var right = fetchResult.count - 1
        var targetIndex: Int?
        var closestDiff: TimeInterval = .infinity
        
        // Binary search for approximate position
        while left <= right {
            let mid = (left + right) / 2
            let asset = fetchResult.object(at: mid)
            
            if let assetDate = asset.creationDate {
                let diff = assetDate.timeIntervalSince(targetDate)
                let absDiff = abs(diff)
                
                if absDiff < closestDiff {
                    closestDiff = absDiff
                    targetIndex = mid
                }
                
                if diff > 0 {
                    // Asset is newer than target, search in older photos (higher indices)
                    left = mid + 1
                } else if diff < 0 {
                    // Asset is older than target, search in newer photos (lower indices)
                    right = mid - 1
                } else {
                    // Exact match
                    break
                }
            } else {
                left = mid + 1
            }
        }
        
        // Fine-tune by checking nearby indices
        if let baseIndex = targetIndex {
            let searchRange = 100
            let startSearch = max(0, baseIndex - searchRange)
            let endSearch = min(fetchResult.count, baseIndex + searchRange)
            
            for i in startSearch..<endSearch {
                let asset = fetchResult.object(at: i)
                if let assetDate = asset.creationDate {
                    let diff = abs(assetDate.timeIntervalSince(targetDate))
                    if diff < closestDiff {
                        closestDiff = diff
                        targetIndex = i
                    }
                }
            }
        }
        
        if let targetIndex = targetIndex {
            let targetAsset = fetchResult.object(at: targetIndex)
            print("✅ [PhotosVM] Found closest asset at index \(targetIndex) of \(fetchResult.count)")
            if let assetDate = targetAsset.creationDate {
                print("✅ [PhotosVM] Asset date: \(assetDate), difference: \(abs(assetDate.timeIntervalSince(targetDate))) seconds")
            }
            
            let beforeCount = 400
            let afterCount = 400
            
            let startIndex = max(0, targetIndex - beforeCount)
            let endIndex = min(fetchResult.count, targetIndex + afterCount)
            
            print("🔄 [PhotosVM] Loading assets from \(startIndex) to \(endIndex) (centered on \(targetIndex))")
            
            var initialAssets: [PHAsset] = []
            initialAssets.reserveCapacity(endIndex - startIndex)
            
            for i in startIndex..<endIndex {
                initialAssets.append(fetchResult.object(at: i))
            }
            
            loadedCount = endIndex
            assets = initialAssets
            state = .loaded
            
            print("✅ [PhotosVM] Loaded \(initialAssets.count) assets around target date")
        } else {
            print("⚠️ [PhotosVM] Could not find asset near target date, loading from start")
            await loadMoreAssets()
        }
    }
    
    private func loadMoreAssets() async {
        guard let fetch = fetchResult else { return }
        guard loadedCount < fetch.count else { return }
        
        let endIndex = min(loadedCount + pageSize, fetch.count)
        print("🔄 [PhotosVM] Loading assets \(loadedCount) to \(endIndex) of \(fetch.count)")
        var newAssets: [PHAsset] = []
        newAssets.reserveCapacity(endIndex - loadedCount)
        
        for index in loadedCount..<endIndex {
            newAssets.append(fetch.object(at: index))
        }
        
        loadedCount = endIndex
        assets.append(contentsOf: newAssets)
        state = .loaded
        print("✅ [PhotosVM] Loaded more assets - total now: \(assets.count)")
    }
    
    private func scheduleRetry(for date: Date) {
        retryTask?.cancel()
        
        print("🔄 [PhotosVM] Scheduling retry for date: \(date)")
        retryTask = Task {
            let delays = [200, 400, 800, 1600, 3200]
            let (start, end) = DateUtility.dayBounds(for: date)
            
            for (index, delay) in delays.enumerated() {
                guard !Task.isCancelled else { return }
                
                print("⏳ [PhotosVM] Retry attempt \(index + 1)/\(delays.count) - waiting \(delay)ms")
                try? await Task.sleep(for: .milliseconds(delay))
                
                guard !Task.isCancelled else { return }
                
                let fetchedAssets = photoService.fetchAssets(from: start, to: end)
                print("🔵 [PhotosVM] Retry \(index + 1): found \(fetchedAssets.count) assets")
                
                if !fetchedAssets.isEmpty {
                    let deduplicated = await deduplicationService.deduplicateAssets(fetchedAssets)
                    assets = deduplicated
                    state = deduplicated.isEmpty ? .empty : .loaded
                    print("✅ [PhotosVM] Retry successful - loaded \(deduplicated.count) assets")
                    return
                }
            }
            
            print("⚠️ [PhotosVM] All retries exhausted, no assets found")
            state = .empty
        }
    }
}