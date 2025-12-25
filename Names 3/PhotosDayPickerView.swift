import SwiftUI
import Photos
import UIKit
import Vision

struct PhotosDayPickerView: View {
    let day: Date
    let onPick: (UIImage) -> Void

    @State private var authStatus: PHAuthorizationStatus = .notDetermined
    @State private var assets: [PHAsset] = []
    @State private var gridSize: CGFloat = 80
    private let imageManager = PHCachingImageManager()
    @State private var isLoading = true

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
                        Text("Enable Photos access in Settings to import photos for this day.")
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
            .navigationTitle(Self.titleFormatter.string(from: day))
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
            .onAppear {
                requestAuthIfNeeded()
            }
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4), spacing: 2) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    ThumbnailView(asset: asset, manager: imageManager, size: CGSize(width: gridSize * UIScreen.main.scale, height: gridSize * UIScreen.main.scale)) { image in
                        onPick(image)
                    }
                    .frame(width: gridSize, height: gridSize)
                    .clipped()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                }
            }
            .padding(2)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func requestAuthIfNeeded() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    authStatus = newStatus
                    if newStatus == .authorized || newStatus == .limited {
                        Task { await loadAssetsForDay() }
                    }
                }
            }
        } else {
            authStatus = status
            if status == .authorized || status == .limited {
                Task { await loadAssetsForDay() }
            }
        }
    }

    private func loadAssetsForDay() async {
        await MainActor.run { isLoading = true }
        let (start, end) = Self.dayBounds(day)
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        let fetch = PHAsset.fetchAssets(with: .image, options: options)

        var fetched: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in fetched.append(asset) }

        let unique = await dedupeAssetsTwoPhase(fetched)
        await MainActor.run {
            self.assets = unique
            self.isLoading = false
        }
        preheat()
    }

    private func preheat() {
        let targetSize = CGSize(width: gridSize * UIScreen.main.scale, height: gridSize * UIScreen.main.scale)
        imageManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFill, options: nil)
    }

    private func dismiss() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let root = window.rootViewController {
            root.dismiss(animated: true)
        }
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        return f
    }()

    private static func dayBounds(_ day: Date) -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? day
        return (start, end)
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

// Two-phase dedupe
private extension PhotosDayPickerView {
    func dedupeAssetsTwoPhase(_ assets: [PHAsset]) async -> [PHAsset] {
        // Phase 1: group by pixel dimensions to avoid comparing obviously different images
        let bySize = Dictionary(grouping: assets) { (asset: PHAsset) in
            SizeKey(w: asset.pixelWidth, h: asset.pixelHeight)
        }

        var kept: [PHAsset] = []
        for (_, group) in bySize {
            if group.count == 1 {
                kept.append(group[0])
                continue
            }

            // Prefilter by aHash clusters to narrow Vision work even if timestamps differ
            let clusters = await clusterByAHash(group)
            for cluster in clusters {
                if cluster.count == 1 {
                    kept.append(cluster[0])
                    continue
                }
                // Phase 2: Vision feature print confirmation inside each candidate cluster
                let confirmed = await confirmDistinctByVision(cluster)
                kept.append(contentsOf: confirmed)
            }
        }

        // Preserve original order (already fetched newest-first)
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
            for (idx, prev) in prints.enumerated() {
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
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            let scale = UIScreen.main.scale
            let size = CGSize(width: 64 * scale, height: 64 * scale)
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
        .contentShape(Rectangle())
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