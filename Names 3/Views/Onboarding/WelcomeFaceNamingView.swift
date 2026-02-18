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
    /// When true (tab context), QuickInput replaces the built-in name field.
    var useQuickInputForName: Bool = false
    @State private var carouselAssets: [PHAsset]? = nil

    private static let windowSize: Int = 500

    var body: some View {
        Group {
            if let assets = carouselAssets {
                WelcomeFaceNamingViewContent(
                    assets: assets,
                    onCarouselAssetsChange: { carouselAssets = $0 },
                    modelContext: modelContext,
                    initialScrollDate: initialScrollDate,
                    onDismiss: onDismiss,
                    useQuickInputForName: useQuickInputForName
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
        .task {
            guard carouselAssets == nil else { return }
            _ = await PhotoLibraryService.shared.requestAuthorization()
            let assets = await Task.detached(priority: .userInitiated) {
                fetchInitialAssets(limit: Self.windowSize)
            }.value
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
    let onDismiss: () -> Void
    let useQuickInputForName: Bool

    func makeUIViewController(context: Context) -> WelcomeFaceNamingViewController {
        let viewController = WelcomeFaceNamingViewController(
            prioritizedAssets: assets,
            modelContext: modelContext,
            initialScrollDate: initialScrollDate,
            useQuickInputForName: useQuickInputForName
        )
        viewController.delegate = context.coordinator
        viewController.onPrioritizedAssetsDidChange = onCarouselAssetsChange
        return viewController
    }

    func updateUIViewController(_ uiViewController: WelcomeFaceNamingViewController, context: Context) {
        uiViewController.updatePrioritizedAssetsIfNeeded(assets)
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

private func fetchInitialAssets(limit: Int) -> [PHAsset] {
    let sortByDate = [NSSortDescriptor(key: "creationDate", ascending: false)]
    let archivedIDs = Set(UserDefaults.standard.stringArray(forKey: WelcomeFaceNamingViewController.archivedAssetIDsKey) ?? [])
    var images: [PHAsset] = []
    let imageOptions = PHFetchOptions()
    imageOptions.sortDescriptors = sortByDate
    let imageResult = PHAsset.fetchAssets(with: .image, options: imageOptions)
    imageResult.enumerateObjects { asset, _, stop in
        if archivedIDs.contains(asset.localIdentifier) { return }
        images.append(asset)
        if images.count >= limit { stop.pointee = true }
    }
    var videos: [PHAsset] = []
    let videoOptions = PHFetchOptions()
    videoOptions.sortDescriptors = sortByDate
    let videoResult = PHAsset.fetchAssets(with: .video, options: videoOptions)
    videoResult.enumerateObjects { asset, _, stop in
        if archivedIDs.contains(asset.localIdentifier) { return }
        videos.append(asset)
        if videos.count >= limit { stop.pointee = true }
    }
    let combined = images + videos
    let sorted = combined.sorted { (a, b) in (a.creationDate ?? .distantPast) > (b.creationDate ?? .distantPast) }
    return Array(sorted.prefix(limit))
}
