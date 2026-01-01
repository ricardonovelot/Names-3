import SwiftUI
import Photos
import UIKit
import Vision

struct PhotosDayPickerView: View {
    let scope: PhotosPickerScope
    let onPick: (UIImage, Date?) -> Void

    @State private var authStatus: PHAuthorizationStatus = .notDetermined
    @State private var assets: [PHAsset] = []
    private let imageManager = PHCachingImageManager()
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    // Retry / observer
    @State private var retryTask: Task<Void, Never>?
    @State private var libraryObserver: LibraryObserver?

    // All-photos paging
    @State private var fetchResult: PHFetchResult<PHAsset>?
    @State private var loadedCount: Int = 0
    private let pageSize: Int = 200

    var body: some View {
        NavigationStack {
            Group {
                switch authStatus {
                case .authorized, .limited:
                    gridView
                case .denied, .restricted:
                    ContentUnavailableView {
                        Label("Photos Access Needed", systemImage: "photo.badge.exclamationmark")
                    } description: {
                        Text("Enable Photos access in Settings to import photos.")
                    } actions: {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                case .notDetermined:
                    ProgressView("Requesting access…")
                @unknown default:
                    gridView
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            }
            .task {
                requestAuthIfNeeded()
            }
            .task(id: scope) {
                if authStatus == .authorized || authStatus == .limited {
                    await loadAssetsForScope()
                }
            }
            .onAppear {
                if libraryObserver == nil {
                    let observer = LibraryObserver {
                        Task { await loadAssetsForScope() }
                    }
                    PHPhotoLibrary.shared().register(observer)
                    libraryObserver = observer
                }
                if authStatus == .authorized || authStatus == .limited {
                    Task { await loadAssetsForScope() }
                } else {
                    requestAuthIfNeeded()
                }
            }
            .onDisappear {
                retryTask?.cancel()
                if let obs = libraryObserver {
                    PHPhotoLibrary.shared().unregisterChangeObserver(obs)
                    libraryObserver = nil
                }
            }
        }
    }

    private var titleText: String {
        switch scope {
        case .day(let day):
            return Self.titleFormatter.string(from: day)
        case .all:
            return "All Photos"
        }
    }

    private var gridView: some View {
        ZStack {
            ScrollView {
                let spacing: CGFloat = 1
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: spacing)], spacing: spacing) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        SquareAssetCell(
                            asset: asset,
                            manager: imageManager,
                            targetSide: 240,
                            onPick: { img, date in
                                onPick(img, date)
                            },
                            onAppearPageTrigger: {
                                handlePaginationIfNeeded(for: asset)
                            }
                        )
                    }
                }
                .padding(spacing)

                if shouldShowPagingSpinner {
                    HStack {
                        Spacer()
                        ProgressView().padding()
                        Spacer()
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))

            if assets.isEmpty && isLoading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Loading photos…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if assets.isEmpty && !isLoading {
                if authStatus == .limited {
                    VStack(spacing: 12) {
                        ContentUnavailableView {
                            Label("No photos available", systemImage: "photo")
                        } description: {
                            Text("Your Photos access is limited. Add photos to the app’s selection.")
                        }
                        Button {
                            presentLimitedLibraryPicker()
                        } label: {
                            Label("Manage Selection", systemImage: "plus.circle")
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("No photos found", systemImage: "photo")
                    } description: {
                        Text("Try a different date or check Photos.")
                    }
                }
            }
        }
    }

    private var shouldShowPagingSpinner: Bool {
        switch scope {
        case .all:
            guard let fetch = fetchResult else { return false }
            return loadedCount < fetch.count
        case .day:
            return false
        }
    }

    private func handlePaginationIfNeeded(for asset: PHAsset) {
        guard case .all = scope else { return }
        guard let fetch = fetchResult else { return }
        guard loadedCount < fetch.count else { return }
        if let idx = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }),
           loadedCount - idx <= 24 {
            Task { await loadMoreAllAssets() }
        }
    }

    private func requestAuthIfNeeded() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                Task { @MainActor in
                    authStatus = newStatus
                    if newStatus == .authorized || newStatus == .limited {
                        await loadAssetsForScope()
                    }
                }
            }
        } else {
            authStatus = status
            if status == .authorized || status == .limited {
                Task { await loadAssetsForScope() }
            }
        }
    }

    private func loadAssetsForScope() async {
        await MainActor.run {
            isLoading = true
            assets = []
            fetchResult = nil
            loadedCount = 0
        }

        switch scope {
        case .day(let day):
            await loadAssetsForDay(day)
        case .all:
            await loadAllAssetsPaged()
        }
    }

    private func loadAssetsForDay(_ day: Date) async {
        try? await Task.sleep(for: .milliseconds(120))

        let (start, end) = Self.dayBounds(day)
        let fetchedStrict = fetchAssets(from: start, to: end)

        await MainActor.run {
            self.assets = fetchedStrict
            self.isLoading = false
        }

        var anyAssets = !fetchedStrict.isEmpty

        if fetchedStrict.isEmpty {
            let cal = Calendar.current
            let relaxedStart = cal.date(byAdding: .hour, value: -12, to: start) ?? start
            let relaxedEnd = cal.date(byAdding: .hour, value: 12, to: end) ?? end
            let relaxed = fetchAssets(from: relaxedStart, to: relaxedEnd)
            if !relaxed.isEmpty {
                let clamped = relaxed.filter { asset in
                    guard let d = asset.creationDate else { return false }
                    return d >= start && d < end
                }
                await MainActor.run {
                    self.assets = clamped
                }
                anyAssets = !clamped.isEmpty
            }
        }

        if !anyAssets {
            scheduleRefetchBackoff(for: day)
            return
        }

        let current = await MainActor.run { self.assets }
        if !current.isEmpty {
            Task {
                let unique = await dedupeAssetsTwoPhase(current)
                await MainActor.run {
                    self.assets = unique
                    preheat()
                }
            }
        }
    }

    private func loadAllAssetsPaged() async {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = PHAsset.fetchAssets(with: .image, options: options)
        await MainActor.run {
            self.fetchResult = fetch
            self.loadedCount = 0
            self.isLoading = fetch.count == 0
        }
        await loadMoreAllAssets()
    }

    @MainActor
    private func loadMoreAllAssets() async {
        guard let fetch = fetchResult else { return }
        guard loadedCount < fetch.count else { return }

        let nextUpper = min(loadedCount + pageSize, fetch.count)
        var newAssets: [PHAsset] = []
        newAssets.reserveCapacity(nextUpper - loadedCount)
        if loadedCount < nextUpper {
            for i in loadedCount..<nextUpper {
                newAssets.append(fetch.object(at: i))
            }
        }
        loadedCount = nextUpper
        assets.append(contentsOf: newAssets)
        isLoading = false

        preheat()
    }

    private func scheduleRefetchBackoff(for day: Date) {
        if retryTask != nil { return }
        retryTask = Task {
            let (start, end) = Self.dayBounds(day)
            let delays = [200, 400, 800, 1600, 3200]
            for ms in delays {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(ms))
                if Task.isCancelled { return }
                let strict = fetchAssets(from: start, to: end)
                if !strict.isEmpty {
                    await MainActor.run {
                        self.assets = strict
                        self.isLoading = false
                    }
                    preheat()
                    retryTask = nil
                    return
                }
                let cal = Calendar.current
                let relaxedStart = cal.date(byAdding: .hour, value: -12, to: start) ?? start
                let relaxedEnd = cal.date(byAdding: .hour, value: 12, to: end) ?? end
                let relaxed = fetchAssets(from: relaxedStart, to: relaxedEnd)
                let clamped = relaxed.filter { asset in
                    guard let d = asset.creationDate else { return false }
                    return d >= start && d < end
                }
                if !clamped.isEmpty {
                    await MainActor.run {
                        self.assets = clamped
                        self.isLoading = false
                    }
                    preheat()
                    retryTask = nil
                    return
                }
            }
            await MainActor.run { self.isLoading = false }
            retryTask = nil
        }
    }

    private func fetchAssets(from start: Date, to end: Date) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        let fetch = PHAsset.fetchAssets(with: .image, options: options)
        var results: [PHAsset] = []
        results.reserveCapacity(fetch.count)
        fetch.enumerateObjects { asset, _, _ in results.append(asset) }
        return results
    }

    private func preheat() {
        let targetSize = CGSize(width: 240, height: 240)
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        return f
    }()

    private static func dayBounds(_ day: Date) -> (Date, Date) {
        let cal = Calendar.current
        if let interval = cal.dateInterval(of: .day, for: day) {
            return (interval.start, interval.end)
        }
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? day
        return (start, end)
    }

    private func presentLimitedLibraryPicker() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let root = window.rootViewController {
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
        }
    }
}

// MARK: - Photo Library Observer
private final class LibraryObserver: NSObject, PHPhotoLibraryChangeObserver {
    let onChange: () -> Void
    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
    }
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { self.onChange() }
    }
}

// Caches
private actor ImageHashCache {
    static let shared = ImageHashCache()
    private var map: [String: UInt64] = [:]
    func get(_ id: String) -> UInt64? { map[id] }
    func set(_ id: String, _ h: UInt64) { map[id] = h }
}

private actor FeaturePrintCache {
    static let shared = FeaturePrintCache()
    private var map: [String: VNFeaturePrintObservation] = [:]
    func get(_ id: String) -> VNFeaturePrintObservation? { map[id] }
    func set(_ id: String, _ fp: VNFeaturePrintObservation) { map[id] = fp }
}

// Hashable key for size grouping
private struct SizeKey: Hashable {
    let w: Int
    let h: Int
}

// Two-phase dedupe (used for day scope)
private extension PhotosDayPickerView {
    func dedupeAssetsTwoPhase(_ assets: [PHAsset]) async -> [PHAsset] {
        let bySize = Dictionary(grouping: assets) { (asset: PHAsset) in
            SizeKey(w: asset.pixelWidth, h: asset.pixelHeight)
        }

        var kept: [PHAsset] = []
        for (_, group) in bySize {
            if group.count == 1 {
                kept.append(group[0])
                continue
            }

            let clusters = await clusterByAHash(group)
            for cluster in clusters {
                if cluster.count == 1 {
                    kept.append(cluster[0])
                    continue
                }
                let confirmed = await confirmDistinctByVision(cluster)
                kept.append(contentsOf: confirmed)
            }
        }

        let keptSet = Set(kept.map { $0.localIdentifier })
        let ordered = assets.filter { keptSet.contains($0.localIdentifier) }
        return ordered
    }

    func clusterByAHash(_ assets: [PHAsset]) async -> [[PHAsset]] {
        var buckets: [[PHAsset]] = []
        var bucketHashes: [[UInt64]] = []
        let threshold = 4

        for asset in assets {
            let h = await computeAHash(for: asset)
            var placed = false
            if let h {
                for i in 0..<bucketHashes.count {
                    if bucketHashes[i].contains(where: { hammingDistance($0, h) <= threshold }) {
                        bucketHashes[i].append(h)
                        buckets[i].append(asset)
                        placed = true
                        break
                    }
                }
            }
            if !placed {
                buckets.append([asset])
                bucketHashes.append(h == nil ? [] : [h!])
            }
        }
        return buckets
    }

    func confirmDistinctByVision(_ assets: [PHAsset]) async -> [PHAsset] {
        var distinct: [PHAsset] = []
        var prints: [VNFeaturePrintObservation] = []
        let threshold: Float = 3.0

        for asset in assets {
            guard let fp = await featurePrint(for: asset) else {
                distinct.append(asset)
                continue
            }
            var isDup = false
            for prev in prints {
                var distance: Float = .infinity
                let status = try? prev.computeDistance(&distance, to: fp)
                if status == nil { continue }
                if distance <= threshold {
                    isDup = true
                    break
                }
            }
            if !isDup {
                prints.append(fp)
                distinct.append(asset)
            }
        }
        return distinct
    }

    func computeAHash(for asset: PHAsset) async -> UInt64? {
        let id = asset.localIdentifier
        if let cached = await ImageHashCache.shared.get(id) { return cached }
        guard let thumb = await requestTinyThumbnail(asset: asset) else { return nil }
        guard let h = aHash(image: thumb) else { return nil }
        await ImageHashCache.shared.set(id, h)
        return h
    }

    func featurePrint(for asset: PHAsset) async -> VNFeaturePrintObservation? {
        let id = asset.localIdentifier
        if let cached = await FeaturePrintCache.shared.get(id) { return cached }

        guard let cg = await requestCGImage(asset: asset) else { return nil }
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        do {
            try handler.perform([request])
            if let obs = request.results?.first as? VNFeaturePrintObservation {
                await FeaturePrintCache.shared.set(id, obs)
                return obs
            }
        } catch {
            return nil
        }
        return nil
    }

    func requestTinyThumbnail(asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            let size = CGSize(width: 64, height: 64)
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { img, _ in
                continuation.resume(returning: img)
            }
        }
    }

    func requestCGImage(asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            let target = CGSize(width: 512, height: 512)
            PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: options) { img, _ in
                continuation.resume(returning: img?.cgImage)
            }
        }
    }

    func aHash(image: UIImage) -> UInt64? {
        let normalized = normalize(image: image)
        guard let cg = normalized.cgImage else { return nil }
        let width = 8
        let height = 8
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var data = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        var luminances = [UInt8](repeating: 0, count: width * height)
        var sum: Int = 0
        var idx = 0
        for i in stride(from: 0, to: data.count, by: 4) {
            let r = Float(data[i + 0])
            let g = Float(data[i + 1])
            let b = Float(data[i + 2])
            let y = UInt8(min(max(0, Int(0.299 * r + 0.587 * g + 0.114 * b)), 255))
            luminances[idx] = y
            sum += Int(y)
            idx += 1
        }
        let avg = sum / (width * height)
        var hash: UInt64 = 0
        for (i, y) in luminances.enumerated() {
            if Int(y) >= avg {
                hash |= (1 << UInt64(i))
            }
        }
        return hash
    }

    func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    func normalize(image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized ?? image
    }
}

private struct ThumbnailView: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let size: CGSize
    let onTap: (UIImage) -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(UIColor.secondarySystemGroupedBackground)
                ProgressView()
            }
        }
        .onTapGesture {
            requestFullImageAndPick()
        }
        .task {
            requestThumb()
        }
    }

    private func requestThumb() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { img, _ in
            if let img { image = img }
        }
    }

    private func requestFullImageAndPick() {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let target = PHImageManagerMaximumSize
        manager.requestImage(for: asset, targetSize: target, contentMode: .aspectFit, options: options) { img, _ in
            if let img { onTap(img) }
        }
    }
}

private struct SquareAssetCell: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let targetSide: CGFloat
    let onPick: (UIImage, Date?) -> Void
    let onAppearPageTrigger: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ThumbnailView(
                asset: asset,
                manager: manager,
                size: CGSize(width: targetSide, height: targetSide)
            ) { img in
                onPick(img, asset.creationDate)
            }
            .frame(width: side, height: side)
            .clipped()
            .contentShape(Rectangle())
            .onAppear {
                onAppearPageTrigger()
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}