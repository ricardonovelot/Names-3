import SwiftUI
import SwiftData
import Photos
import UIKit

/// Name Faces experience: hosts the UIKit flow (carousel, face detection, naming).
/// Uses a sliding window (one page of assets); the VC fetches more when the user scrolls near the end. No full-library load, no cap.
struct WelcomeFaceNamingView: View {
    @Environment(\.modelContext) private var modelContext
    let onDismiss: () -> Void
    var initialScrollDate: Date? = nil
    /// When non-nil (e.g. when switching from Feed), scroll to this asset.
    var initialAssetID: String? = nil
    /// When true (tab context), QuickInput replaces the built-in name field.
    var useQuickInputForName: Bool = false
    var coordinator: CombinedMediaCoordinator? = nil
    /// When true, carousel is the visible mode (consume bridge when becoming visible).
    var isCarouselVisible: Bool = true
    @State private var carouselAssets: [PHAsset]? = nil
    /// Resolved on first load: consumes bridge target from coordinator (Feed→Carousel) or uses passed initialAssetID.
    @State private var resolvedInitialAssetID: String? = nil
    /// When set, VC scrolls to this asset (Feed→Carousel bridge; consumed when carousel becomes visible).
    @State private var scrollToAssetID: String? = nil
    /// Increments when we need to re-run the load task (Feed→Carousel bridge with asset not in list).
    @State private var reloadTrigger: Int = 0

    private static let windowSize: Int = 500

    /// Tries to load carousel assets from cache. Returns nil if cache invalid, stale, or empty.
    private static func loadCarouselAssetsFromCache(limit: Int) -> [PHAsset]? {
        guard !UserDefaults.standard.bool(forKey: WelcomeFaceNamingViewController.cacheInvalidatedKey) else {
            return nil
        }
        let ids = UserDefaults.standard.stringArray(forKey: WelcomeFaceNamingViewController.cachedCarouselAssetIDsKey)
        guard let ids = ids, !ids.isEmpty else { return nil }
        let idsToResolve = Array(ids.prefix(limit))
        let result = PHAsset.fetchAssets(withLocalIdentifiers: idsToResolve, options: nil)
        var byId: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            byId[asset.localIdentifier] = asset
        }
        var ordered: [PHAsset] = []
        for id in idsToResolve {
            if let asset = byId[id] {
                ordered.append(asset)
            }
        }
        guard ordered.count == idsToResolve.count else { return nil }
        return ordered
    }

    private static func saveCarouselCache(assetIDs: [String]) {
        UserDefaults.standard.set(assetIDs, forKey: WelcomeFaceNamingViewController.cachedCarouselAssetIDsKey)
        UserDefaults.standard.set(false, forKey: WelcomeFaceNamingViewController.cacheInvalidatedKey)
    }

    var body: some View {
        Group {
            if let assets = carouselAssets {
                WelcomeFaceNamingViewContent(
                    assets: assets,
                    onCarouselAssetsChange: { carouselAssets = $0 },
                    modelContext: modelContext,
                    initialScrollDate: initialScrollDate,
                    initialAssetID: resolvedInitialAssetID ?? initialAssetID,
                    onDismiss: onDismiss,
                    useQuickInputForName: useQuickInputForName,
                    coordinator: coordinator,
                    scrollToAssetID: $scrollToAssetID
                )
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading photos…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: isCarouselVisible) { _, nowVisible in
            // When switching Feed→Carousel: carousel becomes visible but its task already ran (carouselAssets set).
            // Consume bridge here so we scroll to the feed's asset or reload with that window.
            guard nowVisible, let coord = coordinator else { return }
            let bridgeID = coord.consumeBridgeTarget()
            guard let id = bridgeID else { return }
            if let assets = carouselAssets, assets.contains(where: { $0.localIdentifier == id }) {
                scrollToAssetID = id
                Diagnostics.log("[Bridge] Carousel became visible: scroll to Feed asset \(id)")
            } else {
                Diagnostics.log("[Bridge] Carousel became visible: asset \(id) not in list, reloading window")
                scrollToAssetID = nil
                resolvedInitialAssetID = id
                carouselAssets = nil
                reloadTrigger += 1
            }
        }
        .task(id: reloadTrigger) {
            guard carouselAssets == nil else { return }
            _ = await PhotoLibraryService.shared.requestAuthorization()
            // Consume bridge target first (Feed→Carousel) or use resolvedInitialAssetID from bridge reload
            let bridgeID = coordinator?.consumeBridgeTarget() ?? resolvedInitialAssetID ?? initialAssetID
            resolvedInitialAssetID = bridgeID
            let assets: [PHAsset]
            if let id = bridgeID, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                // Bridge: use same fetcher as Feed for consistent ordering
                let (windowAssets, _) = await NameFacesCarouselAssetFetcher.fetchMixedAssetsAround(
                    targetAsset: asset, rangeDays: 14, limit: 120
                )
                assets = windowAssets.isEmpty ? await NameFacesCarouselAssetFetcher.fetchInitialAssets(limit: Self.windowSize) : windowAssets
            } else {
                // Fast path: try cache first for instant tab open on repeat visits
                if let cached = Self.loadCarouselAssetsFromCache(limit: Self.windowSize) {
                    assets = cached
                } else {
                    assets = await NameFacesCarouselAssetFetcher.fetchInitialAssets(limit: Self.windowSize)
                    if !assets.isEmpty {
                        Self.saveCarouselCache(assetIDs: assets.map { $0.localIdentifier })
                    }
                }
            }
            carouselAssets = assets
        }
    }
}

/// UIKit-based Name Faces flow (carousel, face detection, naming).
private struct WelcomeFaceNamingViewContent: UIViewControllerRepresentable {
    let assets: [PHAsset]
    let onCarouselAssetsChange: ([PHAsset]) -> Void
    let modelContext: ModelContext
    let initialScrollDate: Date?
    let initialAssetID: String?
    let onDismiss: () -> Void
    let useQuickInputForName: Bool
    let coordinator: CombinedMediaCoordinator?
    @Binding var scrollToAssetID: String?

    func makeUIViewController(context: Context) -> WelcomeFaceNamingViewController {
        let viewController = WelcomeFaceNamingViewController(
            prioritizedAssets: assets,
            modelContext: modelContext,
            initialScrollDate: initialScrollDate,
            initialAssetID: initialAssetID,
            useQuickInputForName: useQuickInputForName,
            coordinator: coordinator
        )
        viewController.delegate = context.coordinator
        viewController.onPrioritizedAssetsDidChange = onCarouselAssetsChange
        viewController.onCurrentAssetDidChange = { id in
            Task { @MainActor in
                coordinator?.currentAssetID = id
            }
        }
        return viewController
    }

    func updateUIViewController(_ uiViewController: WelcomeFaceNamingViewController, context: Context) {
        uiViewController.updatePrioritizedAssetsIfNeeded(assets)
        if let id = scrollToAssetID {
            uiViewController.scrollToAssetIDIfNeeded(id)
            DispatchQueue.main.async { scrollToAssetID = nil }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    class Coordinator: NSObject, WelcomeFaceNamingViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
        func welcomeFaceNamingViewControllerDidFinish(_ controller: WelcomeFaceNamingViewController) {
            onDismiss()
        }
    }
}

// MARK: - Carousel: one window (newest first); VC slides and fetches more when user scrolls near end.
