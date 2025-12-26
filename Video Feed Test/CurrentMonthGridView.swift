/*
 UI and behavior spec — CurrentMonthGridView (keep this section up to date)

 Summary
 - Month-scoped media browser with two modes layered together:
   1) Base non-favorites grid (all assets for month; favorites are shown or hidden depending on mode).
   2) Favorites overlay (sections and highlights), animating with matchedGeometryEffect.

 Data & filtering
 - Scope: assets whose creationDate is within [selectedMonthStart, selectedMonthStart + 1 month).
 - Types: images (excluding screenshots), videos restricted heuristically to camera-likely files (IMG_/VID_ filename prefixes).
 - Sort: descending by creationDate (most recent first).
 - Authorization: request Photos.readWrite on first appearance; register for library changes on success (authorized/limited).
 - Reload on PHPhotoLibrary changes; month navigation triggers refetch.

 Primary views and layout
 - Navigation: title shows current month in "LLLL yyyy". Toolbar has chevrons (previous/next month) and a mode toggle (grid <-> heart).
 - Base grid (NonFavoritesGrid):
   - Columns: portrait=3, landscape=5, spacing=0.
   - Shows all month assets when non-favorites mode is active.
   - When favorites mode is active, favorites are replaced by placeholders to preserve grid geometry and enable matchedGeometryEffect.
 - Favorites overlay (FavoritesSectionsView), visible only in favorites mode:
   - Highlights: up to 9 super favorites (3 columns) at the top.
   - Below, sections by day ranges: 21..end, 11..20, 1..10 in a 4-column grid (spacing=6).
   - Up to 8 items per section. If not enough items (especially for current month’s ongoing section), placeholders fill the layout to stable 2x4 blocks.
   - Favorite cells are clipped with a rounded rectangle (8pt corner); matchedGeometryEffect syncs with base grid cells.
 - Placeholder cells are non-interactive and accessibility-hidden.
 - Background uses systemBackground and respects safe areas.

 Interactions
 - Single-tap on a cell toggles asset.isFavorite.
 - Double-tap toggles "super favorite" (persisted via actor-backed store), and auto-favorites if not already a favorite.
 - Mode toggle switches between showing the base grid (all) and the favorites overlay (with base grid showing placeholders for the favorites).
 - Month navigation animates and reloads; matchedGeometryEffect keeps favorites visually consistent between modes.

 Performance policy
 - Minimize main-thread work: filename-based video filtering (PHAssetResource) offloaded to a background queue; UI updates are generation-gated to drop stale results.
 - Thumbnails: PHCachingImageManager with fastFormat + resizeMode.fast, network allowed, degraded images acceptable.
 - Target thumb size: cellSide * screenScale * 0.85 (tuned to reduce decoding cost and memory while being visually crisp).
 - Preheating: rolling window (~40 assets) around the latest visible index; stop old caching when month changes; incremental start/stop based on set differences.
 - Cancellation: in-flight thumb requests are cancelled on disappear.
 - Memory/overdraw: grid uses zero spacing for base content; favorites overlay uses spacing 6 with rounded clips; background set to systemBackground.
 - Expected perf envelopes (debug build guidance):
   - p50 thumbnail latency < 150 ms; p95 < 400 ms; monitor in logs.
   - Steady-state memory: < 120 MB for typical months on device-class under test.
   - Smoothness: 55–60 FPS while scrolling on modern devices.

 Accessibility
 - VoiceOver labels: "Photo, <date>[, Favorite]" or "Video, <date>, <duration>[, Favorite]".
 - Touch target equals the entire cell; placeholders are marked accessibilityHidden.
 - Toolbars have accessibility labels: "Previous month", "Next month", and toggle label reflects current mode.

 Diagnostics and instrumentation
 - Structured logs on: auth flow (with signpost), month reload triggers, preheating decisions (start/stop counts), thumb request begin/end with latency, PhotoKit info keys.
 - Generation token ensures we ignore slow/out-of-date results.
 - Use Instruments to correlate "Missing prefetched properties" messages with user actions; prefer explicit preheating windows to avoid main-queue fetches.

 Edge cases
 - Limited library: behaves as authorized within the allowed scope.
 - iCloud-only assets: degraded images may arrive first; network is allowed; cancellation respected.
 - Empty month: stop all caching, clear IDs, show empty content (with loading cleared).
 */

import SwiftUI
import Photos
import UIKit
import AVFoundation
import Combine
import os
import os.signpost

actor SuperFavoritesStore {
    private let key = "super_favorites_v1"
    private var ids: Set<String>

    init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func all() -> Set<String> { ids }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(id: String) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        persist()
    }

    func set(id: String, value: Bool) {
        if value {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}

@MainActor
final class CurrentMonthGridViewModel: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var authorization: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var assets: [PHAsset] = []
    @Published var isLoading = false
    @Published var selectedMonthStart: Date = {
        let calendar = Calendar.current
        let now = Date()
        return calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
    }()
    @Published var superFavoriteIDs: Set<String> = []

    private let superFavoritesStore = SuperFavoritesStore()
    private var cachedIDs: Set<String> = []
    private var idToIndex: [String: Int] = [:]
    private var loadGeneration: Int = 0
    private var lastPreheatCenter: Int?
    private var lastPreheatTarget: CGSize?

    private let cameraFilenamePrefixes: [String] = ["IMG_", "VID_"]

    override init() {
        super.init()
        if authorization == .authorized || authorization == .limited {
            PHPhotoLibrary.shared().register(self)
        }
        Task { [weak self] in
            guard let self else { return }
            let ids = await superFavoritesStore.all()
            await MainActor.run {
                self.superFavoriteIDs = ids
            }
        }
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        monthCachingManager.stopCachingImagesForAllAssets()
    }

    func onAppear() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        Diagnostics.log("Photos onAppear authorization=\(String(describing: status.rawValue))")
        authorization = status
        switch status {
        case .notDetermined:
            var signpost: OSSignpostID?
            Diagnostics.signpostBegin("AuthRequest", id: &signpost)
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                Task { @MainActor [weak self] in
                    Diagnostics.log("Photos authorization result=\(String(describing: newStatus.rawValue))")
                    Diagnostics.signpostEnd("AuthRequest", id: signpost)
                    self?.authorization = newStatus
                    if newStatus == .authorized || newStatus == .limited {
                        guard let self else { return }
                        PHPhotoLibrary.shared().register(self)
                        self.loadSelectedMonth()
                    }
                }
            }
        case .authorized, .limited:
            loadSelectedMonth()
        default:
            break
        }
    }

    func reload() {
        loadSelectedMonth()
    }

    func isSuperFavorite(_ asset: PHAsset) -> Bool {
        superFavoriteIDs.contains(asset.localIdentifier)
    }

    func toggleSuperFavorite(for asset: PHAsset) {
        Task { [weak self] in
            guard let self else { return }
            let id = asset.localIdentifier
            let isSuper = self.superFavoriteIDs.contains(id)
            if isSuper {
                await self.superFavoritesStore.set(id: id, value: false)
            } else {
                await self.superFavoritesStore.set(id: id, value: true)
                if !asset.isFavorite {
                    self.toggleFavorite(for: asset)
                }
            }
            let refreshed = await self.superFavoritesStore.all()
            await MainActor.run {
                self.superFavoriteIDs = refreshed
            }
        }
    }

    func toggleFavorite(for asset: PHAsset) {
        let targetValue = !asset.isFavorite
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest(for: asset)
            request.isFavorite = targetValue
        }, completionHandler: nil)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        Diagnostics.log("PhotoLibrary didChange received, reloading month")
        Task { @MainActor in
            self.loadSelectedMonth()
        }
    }

    func preheat(center: Int, targetSize: CGSize, window: Int = 40) {
        guard !assets.isEmpty else { return }
        if let lastCenter = lastPreheatCenter, let lastTarget = lastPreheatTarget {
            let delta = abs(center - lastCenter)
            let minStep = max(8, window / 4)
            if delta < minStep && lastTarget == targetSize {
                return
            }
        }
        lastPreheatCenter = center
        lastPreheatTarget = targetSize

        let halfWindow = window / 2
        let range = (center - halfWindow)..<(center + halfWindow)
        let identifiers = Set(assets(in: range).map(\.localIdentifier))
        let toStart = identifiers.subtracting(cachedIDs)
        let toStop = cachedIDs.subtracting(identifiers)

        Diagnostics.log("Preheat center=\(center) window=\(window) start=\(toStart.count) stop=\(toStop.count) target=\(Int(targetSize.width))x\(Int(targetSize.height))")

        if !toStop.isEmpty {
            let stopAssets = toStop.compactMap(asset(withIdentifier:))
            monthCachingManager.stopCachingImages(for: stopAssets,
                                                  targetSize: targetSize,
                                                  contentMode: .aspectFill,
                                                  options: cachingOptions())
            cachedIDs.subtract(stopAssets.map(\.localIdentifier))
        }

        if !toStart.isEmpty {
            let startAssets = toStart.compactMap(asset(withIdentifier:))
            monthCachingManager.startCachingImages(for: startAssets,
                                                   targetSize: targetSize,
                                                   contentMode: .aspectFill,
                                                   options: cachingOptions())
            cachedIDs.formUnion(startAssets.map(\.localIdentifier))
        }
    }

    func preheatForAsset(_ asset: PHAsset, targetSize: CGSize, window: Int = 40) {
        guard let index = idToIndex[asset.localIdentifier] else { return }
        Diagnostics.log("PreheatForAsset id=\(asset.localIdentifier) idx=\(index) window=\(window) target=\(Int(targetSize.width))x\(Int(targetSize.height))")
        preheat(center: index, targetSize: targetSize, window: window)
    }

    func goToPreviousMonth() {
        let calendar = Calendar.current
        guard let newStart = calendar.date(byAdding: DateComponents(month: -1), to: selectedMonthStart) else { return }
        Diagnostics.log("Navigate previousMonth from=\(selectedMonthStart.timeIntervalSince1970) to=\(newStart.timeIntervalSince1970)")
        selectedMonthStart = newStart
        loadSelectedMonth()
    }

    func goToNextMonth() {
        let calendar = Calendar.current
        guard let newStart = calendar.date(byAdding: DateComponents(month: 1), to: selectedMonthStart) else { return }
        Diagnostics.log("Navigate nextMonth from=\(selectedMonthStart.timeIntervalSince1970) to=\(newStart.timeIntervalSince1970)")
        selectedMonthStart = newStart
        loadSelectedMonth()
    }

    private func loadSelectedMonth() {
        isLoading = true
        let bounds = monthBounds()
        let options = PHFetchOptions()

        let typeImage = PHAssetMediaType.image.rawValue
        let typeVideo = PHAssetMediaType.video.rawValue
        let screenshotMask = PHAssetMediaSubtype.photoScreenshot.rawValue

        let datePredicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", bounds.start as NSDate, bounds.end as NSDate)
        let imagesPredicate = NSPredicate(format: "mediaType == %d AND ((mediaSubtypes & %d) == 0)", typeImage, Int(screenshotMask))
        let videosPredicate = NSPredicate(format: "mediaType == %d", typeVideo)
        options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSCompoundPredicate(orPredicateWithSubpredicates: [imagesPredicate, videosPredicate]),
            datePredicate
        ])
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let startTime = CACurrentMediaTime()
        let result = PHAsset.fetchAssets(with: options)
        let count = result.count

        monthCachingManager.stopCachingImagesForAllAssets()
        cachedIDs.removeAll()
        loadGeneration &+= 1
        let generation = loadGeneration

        guard count > 0 else {
            idToIndex.removeAll()
            assets = []
            isLoading = false
            Diagnostics.log("MonthFetch result=0 total=\(String(format: "%.3f", CACurrentMediaTime() - startTime))s")
            return
        }

        let indexSet = IndexSet(integersIn: 0..<count)
        let fetched = result.objects(at: indexSet)
        let fetchElapsed = CACurrentMediaTime() - startTime

        let images = fetched.filter { $0.mediaType == .image }
        let videos = fetched.filter { $0.mediaType == .video }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let filterStart = CACurrentMediaTime()
            // Filename-based heuristic: keep only camera-likely videos
            let filteredVideos: [PHAsset] = videos.filter { asset in
                let resources = PHAssetResource.assetResources(for: asset)
                // Check any resource name; uppercase for case-insensitive compare
                let names = resources.map { $0.originalFilename.uppercased() }
                return names.contains(where: { name in
                    self.cameraFilenamePrefixes.contains(where: { prefix in name.hasPrefix(prefix) })
                })
            }
            let combined = images + filteredVideos
            let filterElapsed = CACurrentMediaTime() - filterStart
            let totalElapsed = CACurrentMediaTime() - startTime

            await MainActor.run {
                guard self.loadGeneration == generation else {
                    Diagnostics.log("MonthFetch drop-stale gen requested=\(generation) current=\(self.loadGeneration)")
                    return
                }
                self.idToIndex = Dictionary(uniqueKeysWithValues: combined.enumerated().map { index, asset in
                    (asset.localIdentifier, index)
                })
                self.assets = combined
                self.isLoading = false
                Diagnostics.log("MonthFetch result=\(combined.count) images=\(images.count) videos=\(videos.count) videosKept=\(filteredVideos.count) fetch=\(String(format: "%.3f", fetchElapsed))s filter=\(String(format: "%.3f", filterElapsed))s total=\(String(format: "%.3f", totalElapsed))s")
            }
        }
    }

    private func monthBounds() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = selectedMonthStart
        let end = calendar.date(byAdding: DateComponents(month: 1), to: start) ?? start
        return (start, end)
    }

    private func assets(in range: Range<Int>) -> [PHAsset] {
        guard !assets.isEmpty else { return [] }
        let lower = max(range.lowerBound, 0)
        let upper = min(range.upperBound, assets.count)
        guard lower < upper else { return [] }
        return Array(assets[lower..<upper])
    }

    private func asset(withIdentifier id: String) -> PHAsset? {
        guard let index = idToIndex[id], assets.indices.contains(index) else { return nil }
        return assets[index]
    }

    private func cachingOptions() -> PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        return options
    }
}

private let monthCachingManager = PHCachingImageManager()
private let thumbnailScaleFactor: CGFloat = 0.85

struct CurrentMonthGridView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CurrentMonthGridViewModel()

    @State private var showFavoritesView = true
    @Namespace private var gridNamespace

    private var favoriteAssets: [PHAsset] {
        model.assets.filter(\.isFavorite)
    }

    private var superFavoriteAssets: [PHAsset] {
        model.assets.filter { $0.isFavorite && model.isSuperFavorite($0) }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: model.selectedMonthStart)
    }

    private var lastDayOfCurrentMonth: Int {
        let calendar = Calendar.current
        return calendar.range(of: .day, in: .month, for: model.selectedMonthStart)?.count ?? 30
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.authorization {
                case .denied, .restricted:
                    deniedView
                default:
                    content
                }
            }
            .navigationTitle(monthTitle)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                            model.goToPreviousMonth()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Previous month")

                    Button {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                            model.goToNextMonth()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel("Next month")

                    Button {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                            showFavoritesView.toggle()
                        }
                    } label: {
                        Image(systemName: showFavoritesView ? "square.grid.3x3" : "heart.fill")
                    }
                    .accessibilityLabel(showFavoritesView ? "Show non-favorites" : "Show favorites")
                }
            }
        }
        .onAppear {
            monthCachingManager.allowsCachingHighQualityImages = false
            model.onAppear()
        }
    }

    private var content: some View {
        ZStack {
            NonFavoritesGrid(
                model: model,
                showFavoritesView: $showFavoritesView,
                gridNamespace: gridNamespace
            )
            FavoritesSectionsView(
                model: model,
                showFavoritesView: $showFavoritesView,
                gridNamespace: gridNamespace,
                highlightsTop: Array(superFavoriteAssets.prefix(9)),
                favoritesProvider: favorites(in:),
                isRangeFullyPast: isRangeFullyPast(_:),
                lastDayOfMonth: lastDayOfCurrentMonth
            )
            .opacity(showFavoritesView ? 1 : 0)
            .allowsHitTesting(showFavoritesView)
            .transition(.opacity)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .animation(.spring(response: 0.55, dampingFraction: 0.88), value: showFavoritesView)
    }

    private func favorites(in range: ClosedRange<Int>) -> [PHAsset] {
        let calendar = Calendar.current
        return favoriteAssets
            .filter { asset in
                guard let date = asset.creationDate else { return false }
                let day = calendar.component(.day, from: date)
                return range.contains(day)
            }
            .sorted { lhs, rhs in
                let leftDate = lhs.creationDate ?? .distantPast
                let rightDate = rhs.creationDate ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                return lhs.localIdentifier > rhs.localIdentifier
            }
    }

    private func isRangeFullyPast(_ range: ClosedRange<Int>) -> Bool {
        let calendar = Calendar.current
        guard calendar.isDate(model.selectedMonthStart, equalTo: Date(), toGranularity: .month) else {
            return true
        }
        let today = calendar.component(.day, from: Date())
        return today > range.upperBound
    }

    private var deniedView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Photos access needed")
                .font(.headline)
            Text("Allow access in Settings to view this month's media.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            HStack(spacing: 16) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
    }
}

private struct NonFavoritesGrid: View {
    @ObservedObject var model: CurrentMonthGridViewModel
    @Binding var showFavoritesView: Bool
    let gridNamespace: Namespace.ID
    var feedMode: Bool = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let spacing: CGFloat = 0
            let columns = columnCount(for: size)
            let cellSide = floor((size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
            let grid = Array(repeating: GridItem(.fixed(cellSide), spacing: spacing, alignment: .top), count: columns)
            let scale = UIScreen.main.scale
            let targetPixels = CGSize(width: cellSide * scale, height: cellSide * scale)
            let requestPixels = CGSize(width: targetPixels.width * thumbnailScaleFactor,
                                       height: targetPixels.height * thumbnailScaleFactor)

            if feedMode {
                let rowsFit = max(1, Int(floor(size.height / max(cellSide, 1))))
                let maxItems = max(1, rowsFit * columns)
                let visible = Array(model.assets.prefix(maxItems).enumerated())

                VStack(spacing: 0) {
                    if model.isLoading {
                        ProgressView()
                            .padding(.vertical, 12)
                    }

                    LazyVGrid(columns: grid, spacing: spacing) {
                        ForEach(visible, id: \.element.localIdentifier) { index, asset in
                            if showFavoritesView && asset.isFavorite {
                                PlaceholderCell()
                                    .frame(width: cellSide, height: cellSide)
                                    .clipped()
                            } else {
                                AssetGridCell(
                                    asset: asset,
                                    targetPixelSize: requestPixels,
                                    isFavorite: asset.isFavorite,
                                    onSingleTap: { model.toggleFavorite(for: asset) },
                                    onDoubleTap: { model.toggleSuperFavorite(for: asset) }
                                )
                                .frame(width: cellSide, height: cellSide)
                                .clipped()
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(assetAccessibilityLabel(for: asset))
                                .matchedGeometryEffect(id: asset.localIdentifier,
                                                       in: gridNamespace,
                                                       isSource: !showFavoritesView && asset.isFavorite)
                                .zIndex(asset.isFavorite ? 1 : 0)
                                .onAppear {
                                    model.preheat(center: index, targetSize: requestPixels)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(height: size.height, alignment: .top)
                .clipped()
            } else {
                ScrollView {
                    if model.isLoading {
                        ProgressView()
                            .padding(.vertical, 12)
                    }

                    LazyVGrid(columns: grid, spacing: spacing) {
                        ForEach(Array(model.assets.enumerated()), id: \.element.localIdentifier) { index, asset in
                            if showFavoritesView && asset.isFavorite {
                                PlaceholderCell()
                                    .frame(width: cellSide, height: cellSide)
                                    .clipped()
                            } else {
                                AssetGridCell(
                                    asset: asset,
                                    targetPixelSize: requestPixels,
                                    isFavorite: asset.isFavorite,
                                    onSingleTap: { model.toggleFavorite(for: asset) },
                                    onDoubleTap: { model.toggleSuperFavorite(for: asset) }
                                )
                                .frame(width: cellSide, height: cellSide)
                                .clipped()
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(assetAccessibilityLabel(for: asset))
                                .matchedGeometryEffect(id: asset.localIdentifier,
                                                       in: gridNamespace,
                                                       isSource: !showFavoritesView && asset.isFavorite)
                                .zIndex(asset.isFavorite ? 1 : 0)
                                .onAppear {
                                    model.preheat(center: index, targetSize: requestPixels)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func columnCount(for size: CGSize) -> Int {
        size.width > size.height ? 5 : 3
    }
}

private struct FavoritesSectionsView: View {
    @ObservedObject var model: CurrentMonthGridViewModel
    @Binding var showFavoritesView: Bool
    let gridNamespace: Namespace.ID
    var feedMode: Bool = false

    let highlightsTop: [PHAsset]
    let favoritesProvider: (ClosedRange<Int>) -> [PHAsset]
    let isRangeFullyPast: (ClosedRange<Int>) -> Bool
    let lastDayOfMonth: Int

    private var highlightIDs: Set<String> {
        Set(highlightsTop.map(\.localIdentifier))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let spacing: CGFloat = 6
            let scale = UIScreen.main.scale

            let topColumns = 3
            let topCellSide = floor((width - CGFloat(topColumns - 1) * spacing) / CGFloat(topColumns))
            let topTargetPixels = CGSize(width: topCellSide * scale, height: topCellSide * scale)
            let topRequestPixels = CGSize(width: topTargetPixels.width * thumbnailScaleFactor,
                                          height: topTargetPixels.height * thumbnailScaleFactor)
            let topGrid = Array(repeating: GridItem(.fixed(topCellSide), spacing: spacing, alignment: .top), count: topColumns)

            let lowerColumns = 4
            let lowerCellSide = floor((width - CGFloat(lowerColumns - 1) * spacing) / CGFloat(lowerColumns))
            let lowerTargetPixels = CGSize(width: lowerCellSide * scale, height: lowerCellSide * scale)
            let lowerRequestPixels = CGSize(width: lowerTargetPixels.width * thumbnailScaleFactor,
                                            height: lowerTargetPixels.height * thumbnailScaleFactor)
            let lowerGrid = Array(repeating: GridItem(.fixed(lowerCellSide), spacing: spacing, alignment: .top), count: lowerColumns)

            if feedMode {
                // Non-scroll, fit into one page. Compute how many lower rows fit after highlights.
                let topRows = Int(ceil(Double(highlightsTop.count) / Double(topColumns)))
                let topHeight = topRows > 0
                    ? (CGFloat(topRows) * topCellSide + CGFloat(max(0, topRows - 1)) * spacing)
                    : 0
                let contentTopPadding: CGFloat = 8
                let contentBottomPadding: CGFloat = 16
                let afterHighlightsSpacing: CGFloat = (topRows > 0 ? 24 : 0)
                let availableHeight = max(0, geometry.size.height - contentTopPadding - contentBottomPadding)
                let lowerRowHeight = lowerCellSide + 6
                let remainingHeight = max(0, availableHeight - topHeight - afterHighlightsSpacing)
                let lowerRowsBudget = max(0, Int(floor(remainingHeight / max(lowerRowHeight, 1))))
                let sectionRowBudgets = computeSectionRowBudgets(totalRows: lowerRowsBudget)

                VStack(alignment: .leading, spacing: 24) {
                    if model.isLoading {
                        ProgressView()
                            .padding(.vertical, 12)
                    }

                    if !highlightsTop.isEmpty {
                        LazyVGrid(columns: topGrid, spacing: spacing) {
                            ForEach(highlightsTop, id: \.localIdentifier) { asset in
                                overlayCell(asset: asset,
                                            cellSide: topCellSide,
                                            targetPixelSize: topRequestPixels)
                            }
                        }
                    }

                    ForEach(FavoritesSectionRange.displayOrder) { section in
                        if let rows = sectionRowBudgets[section], rows > 0 {
                            sectionGrid(range: section.range(lastDayOfMonth: lastDayOfMonth),
                                        columns: lowerGrid,
                                        cellSide: lowerCellSide,
                                        targetPixelSize: lowerRequestPixels,
                                        maxSlotsOverride: rows * lowerColumns)
                        }
                    }
                }
                .padding(.top, contentTopPadding)
                .padding(.bottom, contentBottomPadding)
                .frame(height: geometry.size.height, alignment: .top)
                .clipped()
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if model.isLoading {
                            ProgressView()
                                .padding(.vertical, 12)
                        }

                        if !highlightsTop.isEmpty {
                            LazyVGrid(columns: topGrid, spacing: spacing) {
                                ForEach(highlightsTop, id: \.localIdentifier) { asset in
                                    overlayCell(asset: asset,
                                                cellSide: topCellSide,
                                                targetPixelSize: topRequestPixels)
                                }
                            }
                        }

                        ForEach(FavoritesSectionRange.displayOrder) { section in
                            sectionGrid(range: section.range(lastDayOfMonth: lastDayOfMonth),
                                        columns: lowerGrid,
                                        cellSide: lowerCellSide,
                                        targetPixelSize: lowerRequestPixels)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            }
        }
    }

    @ViewBuilder
    private func sectionGrid(range: ClosedRange<Int>,
                             columns: [GridItem],
                             cellSide: CGFloat,
                             targetPixelSize: CGSize,
                             maxSlotsOverride: Int? = nil) -> some View {
        let filteredFavorites = favoritesProvider(range)
            .filter { !highlightIDs.contains($0.localIdentifier) }
        let columnCount = max(columns.count, 1)
        let defaultMaxSlots = columnCount * 2
        let maxSlots = min(maxSlotsOverride ?? defaultMaxSlots, defaultMaxSlots)
        let hideEmptyRows = isRangeFullyPast(range)
        let slots = arrangedSlots(for: Array(filteredFavorites.prefix(maxSlots)),
                                  range: range,
                                  columnCount: columnCount,
                                  maxSlots: maxSlots,
                                  hideEmptyRows: hideEmptyRows)

        if slots.isEmpty {
            EmptyView()
        } else {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(slots) { slot in
                    switch slot.kind {
                    case .asset(let asset):
                        overlayCell(asset: asset,
                                    cellSide: cellSide,
                                    targetPixelSize: targetPixelSize)
                    case .placeholder:
                        PlaceholderCell()
                            .frame(width: cellSide, height: cellSide)
                            .clipped()
                    }
                }
            }
        }
    }

    private func arrangedSlots(for assets: [PHAsset],
                               range: ClosedRange<Int>,
                               columnCount: Int,
                               maxSlots: Int,
                               hideEmptyRows: Bool) -> [FavoritesSectionSlot] {
        guard columnCount > 0, maxSlots > 0 else { return [] }
        let limitedAssets = Array(assets.prefix(maxSlots))
        if limitedAssets.isEmpty && hideEmptyRows {
            return []
        }

        if hideEmptyRows {
            return limitedAssets.map { asset in
                FavoritesSectionSlot(id: asset.localIdentifier, kind: .asset(asset))
            }
        } else {
            var slots: [FavoritesSectionSlot] = []
            for index in 0..<maxSlots {
                if index < limitedAssets.count {
                    let asset = limitedAssets[index]
                    slots.append(FavoritesSectionSlot(id: asset.localIdentifier, kind: .asset(asset)))
                } else {
                    slots.append(FavoritesSectionSlot(id: placeholderIdentifier(range: range, index: index),
                                                      kind: .placeholder))
                }
            }
            return slots
        }
    }

    private func placeholderIdentifier(range: ClosedRange<Int>, index: Int) -> String {
        "placeholder-\(range.lowerBound)-\(range.upperBound)-\(index)"
    }

    private func overlayCell(asset: PHAsset,
                             cellSide: CGFloat,
                             targetPixelSize: CGSize) -> some View {
        AssetGridCell(
            asset: asset,
            targetPixelSize: targetPixelSize,
            isFavorite: true,
            onSingleTap: nil,
            onDoubleTap: { model.toggleSuperFavorite(for: asset) }
        )
        .frame(width: cellSide, height: cellSide)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .matchedGeometryEffect(id: asset.localIdentifier,
                               in: gridNamespace,
                               isSource: showFavoritesView)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(assetAccessibilityLabel(for: asset))
        .zIndex(2)
        .onAppear {
            model.preheatForAsset(asset, targetSize: targetPixelSize)
        }
        .contextMenu {
            if asset.isFavorite {
                Button(role: .destructive) {
                    model.toggleFavorite(for: asset)
                } label: {
                    Label("Remove from Favorites", systemImage: "heart.slash")
                }
            } else {
                Button {
                    model.toggleFavorite(for: asset)
                } label: {
                    Label("Add to Favorites", systemImage: "heart")
                }
            }

            if model.isSuperFavorite(asset) {
                Button {
                    model.toggleSuperFavorite(for: asset)
                } label: {
                    Label("Remove Super Favorite", systemImage: "star.slash")
                }
            } else {
                Button {
                    model.toggleSuperFavorite(for: asset)
                } label: {
                    Label("Make Super Favorite", systemImage: "star")
                }
            }
        }
    }

    private func computeSectionRowBudgets(totalRows: Int) -> [FavoritesSectionRange: Int] {
        var remaining = max(0, totalRows)
        var dict: [FavoritesSectionRange: Int] = [:]
        for section in FavoritesSectionRange.displayOrder {
            if remaining <= 0 {
                dict[section] = 0
            } else {
                let take = min(2, remaining)
                dict[section] = take
                remaining -= take
            }
        }
        return dict
    }
}

private enum FavoritesSectionRange: CaseIterable, Identifiable {
    case lateMonth
    case midMonth
    case earlyMonth

    var id: String {
        switch self {
        case .lateMonth: return "late"
        case .midMonth: return "mid"
        case .earlyMonth: return "early"
        }
    }

    var priority: Int {
        switch self {
        case .lateMonth: return 0
        case .midMonth: return 1
        case .earlyMonth: return 2
        }
    }

    static var displayOrder: [FavoritesSectionRange] {
        allCases.sorted { $0.priority < $1.priority }
    }

    func range(lastDayOfMonth: Int) -> ClosedRange<Int> {
        switch self {
        case .lateMonth:
            return max(21, 1)...lastDayOfMonth
        case .midMonth:
            return 11...20
        case .earlyMonth:
            return 1...10
        }
    }
}

private struct AssetGridCell: View {
    let asset: PHAsset
    let targetPixelSize: CGSize
    var isFavorite: Bool = false
    var onSingleTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID
    @State private var requestStartTime: CFTimeInterval = 0
    @State private var currentAssetID: String = ""

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.red.opacity(0.65))
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                }
            }
            .overlay {
                if !isFavorite {
                    Rectangle().fill(Color(uiColor: .systemGroupedBackground).opacity(0.65))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap?() }
        .onTapGesture { onSingleTap?() }
        .onAppear {
            handleAppear()
        }
        .onDisappear {
            cancelRequest()
            currentAssetID = ""
            image = nil
        }
        .onChange(of: asset.localIdentifier) { newID in
            guard newID != currentAssetID else { return }
            currentAssetID = newID
            reloadImage()
        }
        .accessibilityAddTraits(asset.mediaType == .video ? .isButton : [])
    }

    private func handleAppear() {
        if currentAssetID != asset.localIdentifier {
            currentAssetID = asset.localIdentifier
            reloadImage()
        } else if image == nil {
            reloadImage()
        } else if requestID == PHInvalidImageRequestID {
            requestImage()
        }
    }

    private func reloadImage() {
        image = nil
        requestImage()
    }

    private func requestImage() {
        cancelRequest()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        requestStartTime = CACurrentMediaTime()
        Diagnostics.log("Thumb request begin id=\(asset.localIdentifier) size=\(Int(targetPixelSize.width))x\(Int(targetPixelSize.height)) fav=\(isFavorite)")

        requestID = monthCachingManager.requestImage(for: asset,
                                                     targetSize: targetPixelSize,
                                                     contentMode: .aspectFill,
                                                     options: options) { image, info in
            let latency = CACurrentMediaTime() - requestStartTime
            PhotoKitDiagnostics.logResultInfo(prefix: "Thumb info id=\(self.asset.localIdentifier)", info: info)
            if let image {
                self.image = image
            }
            Diagnostics.log("Thumb request end id=\(self.asset.localIdentifier) hasImage=\(image != nil) dt=\(String(format: "%.3f", latency))s")
        }
    }

    private func cancelRequest() {
        if requestID != PHInvalidImageRequestID {
            Diagnostics.log("Thumb request cancel id=\(asset.localIdentifier)")
            monthCachingManager.cancelImageRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
    }
}

private struct PlaceholderCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(uiColor: .label).opacity(0.1))
            .accessibilityHidden(true)
    }
}

private func assetAccessibilityLabel(for asset: PHAsset) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    let dateString = asset.creationDate.map { formatter.string(from: $0) } ?? "Unknown date"
    let favoriteSuffix = asset.isFavorite ? ", Favorite" : ""
    switch asset.mediaType {
    case .video:
        let duration = formatDuration(asset.duration)
        return "Video, \(dateString), \(duration)\(favoriteSuffix)"
    case .image:
        return "Photo, \(dateString)\(favoriteSuffix)"
    default:
        return dateString
    }
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let totalSeconds = Int(seconds.rounded())
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
        return String(format: "%d:%02d", minutes, secs)
    }
}

private struct FavoritesSectionSlot: Identifiable {
    enum Kind {
        case asset(PHAsset)
        case placeholder
    }

    let id: String
    let kind: Kind
}

struct MonthPageGridView: View {
    let monthStart: Date

    @StateObject private var model = CurrentMonthGridViewModel()
    @State private var showFavoritesView = true
    @Namespace private var gridNamespace

    private var favoriteAssets: [PHAsset] {
        model.assets.filter(\.isFavorite)
    }

    private var superFavoriteAssets: [PHAsset] {
        model.assets.filter { $0.isFavorite && model.isSuperFavorite($0) }
    }

    private var lastDayOfCurrentMonth: Int {
        let calendar = Calendar.current
        return calendar.range(of: .day, in: .month, for: model.selectedMonthStart)?.count ?? 30
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NonFavoritesGrid(
                model: model,
                showFavoritesView: $showFavoritesView,
                gridNamespace: gridNamespace,
                feedMode: true
            )
            FavoritesSectionsView(
                model: model,
                showFavoritesView: $showFavoritesView,
                gridNamespace: gridNamespace,
                feedMode: true,
                highlightsTop: Array(superFavoriteAssets.prefix(9)),
                favoritesProvider: favorites(in:),
                isRangeFullyPast: isRangeFullyPast(_:),
                lastDayOfMonth: lastDayOfCurrentMonth
            )
            .opacity(showFavoritesView ? 1 : 0)
            .allowsHitTesting(showFavoritesView)
            .transition(.opacity)

            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                    showFavoritesView.toggle()
                }
            } label: {
                Image(systemName: showFavoritesView ? "square.grid.3x3" : "heart.fill")
                    .font(.title2)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
            .accessibilityLabel(showFavoritesView ? "Show non-favorites" : "Show favorites")
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .animation(.spring(response: 0.55, dampingFraction: 0.88), value: showFavoritesView)
        .onAppear {
            monthCachingManager.allowsCachingHighQualityImages = false
            if model.selectedMonthStart != monthStart {
                model.selectedMonthStart = monthStart
            }
            model.onAppear()
        }
    }

    private func favorites(in range: ClosedRange<Int>) -> [PHAsset] {
        let calendar = Calendar.current
        return favoriteAssets
            .filter { asset in
                guard let date = asset.creationDate else { return false }
                let day = calendar.component(.day, from: date)
                return range.contains(day)
            }
            .sorted { lhs, rhs in
                let leftDate = lhs.creationDate ?? .distantPast
                let rightDate = rhs.creationDate ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                return lhs.localIdentifier > rhs.localIdentifier
            }
    }

    private func isRangeFullyPast(_ range: ClosedRange<Int>) -> Bool {
        let calendar = Calendar.current
        guard calendar.isDate(model.selectedMonthStart, equalTo: Date(), toGranularity: .month) else {
            return true
        }
        let today = calendar.component(.day, from: Date())
        return today > range.upperBound
    }
}

struct MonthFeedView: View {
    private let monthsAhead = 24

    private var baseMonthStart: Date {
        let calendar = Calendar.current
        let now = Date()
        return calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
    }

    private var monthOffsets: [Int] {
        Array(0...monthsAhead)
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(monthOffsets, id: \.self) { offset in
                    let monthDate = offsetMonth(from: baseMonthStart, by: offset)
                    MonthPageGridView(monthStart: monthDate)
                        .containerRelativeFrame(.vertical)
                        .id(offset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
    }

    private func offsetMonth(from start: Date, by delta: Int) -> Date {
        Calendar.current.date(byAdding: DateComponents(month: delta), to: start) ?? start
    }
}