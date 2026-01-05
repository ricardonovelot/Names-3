import SwiftUI
import Photos
import SwiftData
import CoreLocation

struct PhotosInlineView: View {
    @Environment(\.modelContext) private var modelContext
    let contactsContext: ModelContext
    let onPhotoPicked: (UIImage, Date?) -> Void
    let isVisible: Bool
    
    @StateObject private var viewModel = PhotosInlineViewModel()
    
    init(contactsContext: ModelContext, isVisible: Bool = true, onPhotoPicked: @escaping (UIImage, Date?) -> Void) {
        self.contactsContext = contactsContext
        self.isVisible = isVisible
        self.onPhotoPicked = onPhotoPicked
    }
    
    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                loadingView
            case .loaded:
                if viewModel.photoGroups.isEmpty {
                    emptyStateView
                } else {
                    photosListView
                }
            case .empty:
                emptyStateView
            case .error(let message):
                errorView(message: message)
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .onAppear {
            if isVisible {
                Task {
                    await viewModel.loadPhotos()
                }
            }
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue && viewModel.state == PhotosInlineViewModel.State.idle {
                Task {
                    await viewModel.loadPhotos()
                }
            }
        }
    }
    
    private var photosListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(viewModel.photoGroups) { group in
                    PhotoGroupSectionView(
                        group: group,
                        isLast: group.id == viewModel.photoGroups.last?.id,
                        onPhotoTapped: { asset in
                            loadAndPickPhoto(asset)
                        }
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.bottom)
    }
    
    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading photos…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No photos found", systemImage: "photo")
        } description: {
            Text("No photos available in your library.")
        }
    }
    
    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task {
                    await viewModel.loadPhotos()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func loadAndPickPhoto(_ asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            if let image = image {
                onPhotoPicked(image, asset.creationDate)
            }
        }
    }
}

// MARK: - Photo Group Section View

private struct PhotoGroupSectionView: View {
    let group: PhotoGroup
    let isLast: Bool
    let onPhotoTapped: (PHAsset) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 10), count: 3), spacing: 10) {
                ForEach(group.representativeAssets, id: \.localIdentifier) { asset in
                    PhotoThumbnailView(asset: asset)
                        .frame(height: 110)
                        .onTapGesture {
                            onPhotoTapped(asset)
                        }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, isLast ? 0 : 16)
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(group.title)
                    .font(.title)
                    .bold()
                Spacer()
            }
            .padding(.leading)
            .padding(.trailing, 14)
            
            Text(group.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(.bottom, 4)
        .contentShape(.rect)
    }
}

// MARK: - Photo Thumbnail View

private struct PhotoThumbnailView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    
    private let imageManager = PHCachingImageManager()
    
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                    
                    LinearGradient(
                        gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.7)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    Color(uiColor: .secondarySystemGroupedBackground)
                    ProgressView()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        
        let targetSize = CGSize(width: 300, height: 300)
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                self.image = result
            }
        }
    }
}

// MARK: - View Model

@MainActor
class PhotosInlineViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case error(String)
        
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.loaded, .loaded), (.empty, .empty):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    
    @Published var state: State = .idle
    @Published var photoGroups: [PhotoGroup] = []
    
    private var locationCache: [String: String] = [:]
    
    func loadPhotos() async {
        state = .loading
        
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if status == .authorized || status == .limited {
            await fetchAndGroupPhotos()
            return
        }
        
        if status == .notDetermined {
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if newStatus == .authorized || newStatus == .limited {
                await fetchAndGroupPhotos()
            } else {
                state = .error("Photos access is required")
            }
        } else {
            state = .error("Photos access is required")
        }
    }
    
    private func fetchAndGroupPhotos() async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let assets = PHAsset.fetchAssets(with: fetchOptions)
        
        guard assets.count > 0 else {
            state = .empty
            return
        }
        
        var allAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            allAssets.append(asset)
        }
        
        // Filter out screenshots-only groups
        let filteredAssets = allAssets.filter { !isScreenshot($0) }
        
        guard !filteredAssets.isEmpty else {
            state = .empty
            return
        }
        
        let groups = await groupPhotosByPlaceAndTime(filteredAssets)
        
        self.photoGroups = groups.reversed()
        self.state = groups.isEmpty ? .empty : .loaded
    }
    
    private func isScreenshot(_ asset: PHAsset) -> Bool {
        // Check if it's a screenshot based on mediaSubtypes
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            return true
        }
        
        // Additional check: screenshots typically don't have location data
        // and have specific dimensions matching device screens
        if asset.location == nil {
            let pixelWidth = asset.pixelWidth
            let pixelHeight = asset.pixelHeight
            
            // Common iOS screenshot dimensions (can add more)
            let screenshotDimensions: [(Int, Int)] = [
                (1170, 2532), // iPhone 12/13/14 Pro
                (1179, 2556), // iPhone 14 Pro
                (1284, 2778), // iPhone 12/13/14 Pro Max
                (1125, 2436), // iPhone X/XS/11 Pro
                (828, 1792),  // iPhone 11/XR
                (1242, 2688), // iPhone XS Max
                (750, 1334),  // iPhone 6/7/8
                (1242, 2208), // iPhone 6/7/8 Plus
                (2048, 2732), // iPad Pro 12.9"
                (1668, 2388), // iPad Pro 11"
                (1620, 2160), // iPad 10.2"
            ]
            
            for (width, height) in screenshotDimensions {
                if (pixelWidth == width && pixelHeight == height) || 
                   (pixelWidth == height && pixelHeight == width) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func groupPhotosByPlaceAndTime(_ assets: [PHAsset]) async -> [PhotoGroup] {
        var groups: [PhotoGroup] = []
        
        // First, group by day
        let calendar = Calendar.current
        let groupedByDay = Dictionary(grouping: assets) { asset -> Date in
            guard let date = asset.creationDate else { return Date.distantPast }
            return calendar.startOfDay(for: date)
        }
        
        print("📍 [PhotosInline] Total days: \(groupedByDay.count)")
        
        // Sort day groups by date (newest first)
        var dayGroups: [(date: Date, assets: [PHAsset])] = groupedByDay.map { ($0.key, $0.value) }
            .sorted { $0.date > $1.date }
        
        let locationThreshold: CLLocationDistance = 20000 // 20 kilometers for camping/hiking trips
        let maxDayGap: Int = 7 // Allow up to 7 days for multi-day trips
        
        var processed = Set<Date>()
        var mergedGroups: [[PHAsset]] = []
        
        for i in 0..<dayGroups.count {
            let (currentDate, currentAssets) = dayGroups[i]
            
            if processed.contains(currentDate) {
                continue
            }
            
            var groupToMerge = currentAssets
            processed.insert(currentDate)
            
            let currentLocations = currentAssets.compactMap { $0.location }
            let currentAvgLocation = currentLocations.isEmpty ? nil : averageLocation(currentLocations)
            
            print("📍 [PhotosInline] Day \(currentDate): \(currentAssets.count) photos, \(currentLocations.count) with location")
            
            // Look ahead to find nearby days that should merge
            for j in (i + 1)..<dayGroups.count {
                let (otherDate, otherAssets) = dayGroups[j]
                
                if processed.contains(otherDate) {
                    continue
                }
                
                let dayDiff = abs(calendar.dateComponents([.day], from: currentDate, to: otherDate).day ?? 999)
                
                if dayDiff > maxDayGap {
                    continue // Too far apart in time
                }
                
                let otherLocations = otherAssets.compactMap { $0.location }
                let otherAvgLocation = otherLocations.isEmpty ? nil : averageLocation(otherLocations)
                
                let shouldMerge: Bool
                if let currentLoc = currentAvgLocation, let otherLoc = otherAvgLocation {
                    let distance = currentLoc.distance(from: otherLoc)
                    shouldMerge = distance <= locationThreshold
                    if shouldMerge {
                        print("📍 [PhotosInline] Merging days (distance: \(Int(distance))m)")
                    }
                } else if currentAvgLocation == nil && otherAvgLocation == nil {
                    // Both have no location - merge if within time gap
                    shouldMerge = true
                } else {
                    shouldMerge = false
                }
                
                if shouldMerge {
                    groupToMerge.append(contentsOf: otherAssets)
                    processed.insert(otherDate)
                }
            }
            
            mergedGroups.append(groupToMerge)
        }
        
        print("📍 [PhotosInline] Created \(mergedGroups.count) groups from \(dayGroups.count) days")
        
        // Create PhotoGroup objects
        for groupAssets in mergedGroups {
            let locations = groupAssets.compactMap { $0.location }
            let avgLocation = locations.isEmpty ? nil : averageLocation(locations)
            
            if avgLocation != nil {
                print("📍 [PhotosInline] Group has location data")
            } else {
                print("📍 [PhotosInline] Group has NO location data (\(groupAssets.count) photos)")
            }
            
            let group = await createPhotoGroup(from: groupAssets, location: avgLocation)
            groups.append(group)
        }
        
        return groups
    }
    
    private func averageLocation(_ locations: [CLLocation]) -> CLLocation? {
        guard !locations.isEmpty else { return nil }
        
        let avgLat = locations.map { $0.coordinate.latitude }.reduce(0, +) / Double(locations.count)
        let avgLon = locations.map { $0.coordinate.longitude }.reduce(0, +) / Double(locations.count)
        
        return CLLocation(latitude: avgLat, longitude: avgLon)
    }
    
    private func createPhotoGroup(from assets: [PHAsset], location: CLLocation?) async -> PhotoGroup {
        let representative = selectRepresentativePhotos(from: assets, count: 3)
        
        let date = assets.first?.creationDate ?? Date()
        let locationName: String? = nil
        
        return PhotoGroup(
            assets: assets,
            representativeAssets: representative,
            date: date,
            location: location,
            locationName: locationName
        )
    }
    
    private func selectRepresentativePhotos(from assets: [PHAsset], count: Int) -> [PHAsset] {
        var scored: [(asset: PHAsset, score: Double)] = []
        
        for asset in assets {
            var score: Double = 0
            
            // Skip screenshots for representative photos
            if isScreenshot(asset) {
                score -= 1000
            }
            
            if asset.isFavorite {
                score += 10
            }
            
            if let aestheticScore = asset.value(forKey: "overallAestheticScore") as? Double {
                score += aestheticScore * 5
            }
            
            let mediaSubtypes = asset.mediaSubtypes
            if mediaSubtypes.contains(.photoLive) {
                score += 2
            }
            if mediaSubtypes.contains(.photoHDR) {
                score += 1
            }
            if mediaSubtypes.contains(.photoPanorama) {
                score += 3
            }
            
            // Prefer photos with location data
            if asset.location != nil {
                score += 3
            }
            
            scored.append((asset, score))
        }
        
        let sorted = scored.sorted { $0.score > $1.score }
        return Array(sorted.prefix(count).map { $0.asset })
    }
}

// MARK: - Photo Group Model

struct PhotoGroup: Identifiable, Hashable {
    let id = UUID()
    let assets: [PHAsset]
    let representativeAssets: [PHAsset]
    let date: Date
    let location: CLLocation?
    let locationName: String?
    
    var title: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date)
    }
    
    var subtitle: String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "\(assets.count) photos • Today"
        } else if calendar.isDateInYesterday(date) {
            return "\(assets.count) photos • Yesterday"
        }
        
        let components = calendar.dateComponents([.year, .month, .day], from: date, to: now)
        
        if let year = components.year, year > 0 {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "yyyy"
            let yearString = formatter.string(from: date)
            let yearWord = year == 1 ? "year ago" : "years ago"
            return "\(assets.count) photos • \(yearString), \(year) \(yearWord)"
        } else if let month = components.month, month > 0 {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "MMMM"
            let monthString = formatter.string(from: date)
            let monthWord = month == 1 ? "month ago" : "months ago"
            return "\(assets.count) photos • \(monthString), \(month) \(monthWord)"
        } else if let day = components.day, day > 0 {
            if day < 7 {
                let formatter = DateFormatter()
                formatter.locale = Locale.current
                formatter.dateFormat = "EEEE"
                let dayString = formatter.string(from: date)
                return "\(assets.count) photos • \(dayString)"
            } else {
                let dayWord = day == 1 ? "day ago" : "days ago"
                return "\(assets.count) photos • \(day) \(dayWord)"
            }
        } else {
            return "\(assets.count) photos • Today"
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PhotoGroup, rhs: PhotoGroup) -> Bool {
        lhs.id == rhs.id
    }
}