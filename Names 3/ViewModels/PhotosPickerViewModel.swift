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
    
    // MARK: - Initialization
    
    init(
        scope: PhotosPickerScope,
        photoService: PhotoLibraryServiceProtocol = PhotoLibraryService.shared,
        deduplicationService: DeduplicationService = .shared
    ) {
        self.scope = scope
        self.photoService = photoService
        self.deduplicationService = deduplicationService
    }
    
    // MARK: - Public Methods
    
    func requestAuthorizationIfNeeded() {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorizationStatus = currentStatus
        
        if currentStatus == .notDetermined {
            state = .requestingAuthorization
            
            Task {
                let newStatus = await photoService.requestAuthorization()
                authorizationStatus = newStatus
                
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
                await loadAllAssetsPaged()
            }
        }
        
        await loadTask?.value
    }
    
    func reloadForScope(_ newScope: PhotosPickerScope) {
        guard newScope != scope else { return }
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
            Task {
                await loadMoreAssets()
            }
        }
    }
    
    func startObservingChanges() {
        guard changeObserver == nil else { return }
        
        changeObserver = photoService.observeChanges { [weak self] in
            Task { @MainActor [weak self] in
                await self?.loadAssets()
            }
        }
    }
    
    func stopObservingChanges() {
        if let observer = changeObserver {
            photoService.unregisterObserver(observer)
            changeObserver = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func cleanup() {
        loadTask?.cancel()
        retryTask?.cancel()
        stopObservingChanges()
    }
    
    private func loadAssetsForDay(_ date: Date) async {
        try? await Task.sleep(for: .milliseconds(120))
        
        guard !Task.isCancelled else { return }
        
        let (start, end) = DateUtility.dayBounds(for: date)
        var fetchedAssets = photoService.fetchAssets(from: start, to: end)
        
        if fetchedAssets.isEmpty {
            let calendar = Calendar.current
            let relaxedStart = calendar.date(byAdding: .hour, value: -12, to: start) ?? start
            let relaxedEnd = calendar.date(byAdding: .hour, value: 12, to: end) ?? end
            
            let relaxedAssets = photoService.fetchAssets(from: relaxedStart, to: relaxedEnd)
            fetchedAssets = relaxedAssets.filter { asset in
                guard let creationDate = asset.creationDate else { return false }
                return creationDate >= start && creationDate < end
            }
        }
        
        guard !Task.isCancelled else { return }
        
        if fetchedAssets.isEmpty {
            assets = []
            state = .empty
            scheduleRetry(for: date)
            return
        }
        
        let deduplicated = await deduplicationService.deduplicateAssets(fetchedAssets)
        
        guard !Task.isCancelled else { return }
        
        assets = deduplicated
        state = deduplicated.isEmpty ? .empty : .loaded
    }
    
    private func loadAllAssetsPaged() async {
        let fetchResult = photoService.fetchAssets(for: .all)
        self.fetchResult = fetchResult
        
        guard fetchResult.count > 0 else {
            state = .empty
            return
        }
        
        await loadMoreAssets()
    }
    
    private func loadMoreAssets() async {
        guard let fetch = fetchResult else { return }
        guard loadedCount < fetch.count else { return }
        
        let endIndex = min(loadedCount + pageSize, fetch.count)
        var newAssets: [PHAsset] = []
        newAssets.reserveCapacity(endIndex - loadedCount)
        
        for index in loadedCount..<endIndex {
            newAssets.append(fetch.object(at: index))
        }
        
        loadedCount = endIndex
        assets.append(contentsOf: newAssets)
        state = .loaded
    }
    
    private func scheduleRetry(for date: Date) {
        retryTask?.cancel()
        
        retryTask = Task {
            let delays = [200, 400, 800, 1600, 3200]
            let (start, end) = DateUtility.dayBounds(for: date)
            
            for delay in delays {
                guard !Task.isCancelled else { return }
                
                try? await Task.sleep(for: .milliseconds(delay))
                
                guard !Task.isCancelled else { return }
                
                let fetchedAssets = photoService.fetchAssets(from: start, to: end)
                
                if !fetchedAssets.isEmpty {
                    let deduplicated = await deduplicationService.deduplicateAssets(fetchedAssets)
                    assets = deduplicated
                    state = deduplicated.isEmpty ? .empty : .loaded
                    return
                }
            }
            
            state = .empty
        }
    }
}