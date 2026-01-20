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
    
    private var loadTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    
    private var reloadDebounceTask: Task<Void, Never>?
    private var isReloadingSuppressed = false
    
    private var initialScrollDate: Date?
    private var lastKnownAssetCount: Int = 0  // Track asset count to detect real changes
    
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
        if let observer = changeObserver {
            photoService.unregisterObserver(observer)
        }
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
        
        loadTask = Task {
            switch scope {
            case .day(let date):
                await loadAssetsForDay(date)
            case .all:
                await loadAllAssets()
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
        // Pagination is no longer needed - all assets loaded upfront
    }
    
    func startObservingChanges() {
        guard changeObserver == nil else { return }
        
        print("🔵 [PhotosVM] Starting photo library change observation")
        changeObserver = photoService.observeChanges { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                print("🔄 [PhotosVM] Photo library changed, checking if reload needed")
                
                self.reloadDebounceTask?.cancel()
                
                guard !self.isReloadingSuppressed else {
                    print("⏸️ [PhotosVM] Reload suppressed during user interaction")
                    return
                }
                
                // Check if asset count actually changed before reloading
                let currentCount = self.photoService.fetchAssets(for: self.scope).count
                
                if currentCount == self.lastKnownAssetCount {
                    print("⏭️ [PhotosVM] Asset count unchanged (\(currentCount)), skipping reload")
                    return
                }
                
                print("🔄 [PhotosVM] Asset count changed: \(self.lastKnownAssetCount) → \(currentCount), scheduling reload")
                
                self.reloadDebounceTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    
                    guard !Task.isCancelled else { return }
                    guard !self.isReloadingSuppressed else { return }
                    
                    print("🔄 [PhotosVM] Executing reload for asset count change")
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
        
        if suppress {
            reloadDebounceTask?.cancel()
            print("🔵 [PhotosVM] Cancelled pending debounced reload")
        }
    }
    
    // MARK: - Private Methods
    
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
    
    private func loadAllAssets() async {
        print("🔵 [PhotosVM] Loading all assets")
        let fetchResult = photoService.fetchAssets(for: .all)
        self.fetchResult = fetchResult
        print("🔵 [PhotosVM] Total assets available: \(fetchResult.count)")
        
        guard fetchResult.count > 0 else {
            state = .empty
            print("⚠️ [PhotosVM] No assets in library")
            return
        }
        
        print("📦 [PhotosVM] Enumerating all \(fetchResult.count) assets")
        var allAssets: [PHAsset] = []
        allAssets.reserveCapacity(fetchResult.count)
        
        fetchResult.enumerateObjects { asset, _, _ in
            allAssets.append(asset)
        }
        
        print("✅ [PhotosVM] Enumerated \(allAssets.count) assets")
        
        guard !Task.isCancelled else {
            print("⚠️ [PhotosVM] Task cancelled during enumeration")
            return
        }
        
        assets = allAssets
        lastKnownAssetCount = allAssets.count  // Store the count
        state = .loaded
        
        print("✅ [PhotosVM] All assets loaded successfully")
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