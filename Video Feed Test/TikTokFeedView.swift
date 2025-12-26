import SwiftUI
import Photos
import UIKit

struct TikTokFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TikTokFeedViewModel
    @State private var index: Int = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var didSetInitialIndex = false
    @State private var readyVideoIDs: Set<String> = []
    @State private var isSharing = false
    @State private var shareItems: [Any] = []
    @State private var isPreparingShare = false
    @State private var shareTempURLs: [URL] = []
    @State private var pendingShareURL: URL?
    @State private var showSettings = false

    @StateObject private var options = OptionsCoordinator()
    @State private var isPagingInteracting = false

    @StateObject private var appleMusic = MusicLibraryModel()
    @State private var showDateActions = false
    @State private var isQuickPanelExpanded = false
    @Namespace private var quickGlassNS

    init(mode: TikTokFeedViewModel.FeedMode) {
        _viewModel = StateObject(wrappedValue: TikTokFeedViewModel(mode: mode))
    }
    
    var body: some View {
        ZStack {
            if viewModel.authorization == .denied || viewModel.authorization == .restricted {
                deniedView
            } else if viewModel.isLoading {
                ProgressView().scaleEffect(1.2)
            } else if viewModel.items.isEmpty {
                emptyView
            } else {
                PagedCollectionView(items: viewModel.items,
                                    index: $index,
                                    id: { $0.id },
                                    onPrefetch: handlePrefetch(indices:size:),
                                    onCancelPrefetch: handleCancelPrefetch(indices:size:),
                                    isPageReady: { idx in
                    guard viewModel.items.indices.contains(idx) else { return true }
                    switch viewModel.items[idx].kind {
                    case .video(let a):
                        return readyVideoIDs.contains(a.localIdentifier)
                    case .photoCarousel:
                        return true
                    }
                },
                                    content: { i, item, isActive in
                    switch item.kind {
                    case .video(let asset):
                        AnyView(
                            TikTokPlayerView(
                                asset: asset,
                                isActive: isActive,
                                pinnedMode: options.progress > 0.001,
                                noCropMode: true
                            )
                            .id(item.id)
                            .optionsPinnedTopTransform(progress: options.progress)
                            .animation(options.isInteracting ? nil : .interpolatingSpring(stiffness: 220, damping: 28), value: options.progress)
                        )
                    case .photoCarousel(let assets):
                        if FeatureFlags.enablePhotoPosts {
                            AnyView(
                                PhotoCarouselPostView(assets: assets)
                                    .id(item.id)
                            )
                        } else {
                            AnyView(
                                EmptyView()
                                    .id(item.id)
                            )
                        }
                    }
                },
                                    onScrollInteracting: { interacting in
                    isPagingInteracting = interacting
                })
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    OptionsSheet(
                        options: options,
                        appleMusic: appleMusic,
                        currentAssetID: currentVideoAsset()?.localIdentifier,
                        onDelete: { deleteCurrentVideo() },
                        onShare: { prepareShare() },
                        onOpenSettings: { showSettings = true }
                    )
                    .zIndex(2)
                }
                .safeAreaInset(edge: .bottom) {
                    HStack(alignment: .bottom) {
                       
                        if !isQuickPanelExpanded {
                            VStack(alignment: .leading, spacing: 6) {
                                if let rel = relativeLabelForCurrentItem() {
                                    Text(rel)
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .liquidGlass(in: Capsule())
                                        .background(
                                            Capsule().fill(Color.black.opacity(0.10))
                                                .frame(maxWidth: .infinity)
                                        )
                                        .padding(.leading, 12)
                                        .accessibilityHidden(true)
                                }
                                
                                if let label = dateLabelForCurrentItem() {
                                    Text(label)
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .liquidGlass(in: Capsule())
                                        .background(
                                            Capsule().fill(Color.black.opacity(0.10))
                                                .frame(maxWidth: .infinity)
                                        )
                                        .padding(.leading, 12)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showDateActions = true
                            }
                            .animation(nil, value: index)
                        }

                        Spacer()

                        VStack(spacing: 10) {
                            if !isQuickPanelExpanded {
                                OptionsDragHandle(
                                    options: options,
                                    openDistance: min(max(UIScreen.main.bounds.size.height * 0.22, 280), 420)
                                )
                                .animation(nil, value: index)
                            }

                            if !isQuickPanelExpanded {
                                Button {
                                    var t = Transaction()
                                    t.animation = .spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)
                                    withTransaction(t) {
                                        isQuickPanelExpanded = true
                                    }
                                } label: {
                                    let collapsedCorner: CGFloat = 24
                                    ZStack {
                                        RoundedRectangle(cornerRadius: collapsedCorner, style: .continuous)
                                            .fill(Color.black.opacity(0.28))
                                            .liquidGlass(in: RoundedRectangle(cornerRadius: collapsedCorner, style: .continuous), stroke: false)
                                            .matchedGeometryEffect(id: "quickGlassBG", in: quickGlassNS)
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                    .frame(width: 48, height: 48)
                                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open panel")
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        } 
        .onAppear { 
            viewModel.onAppear()
            NotificationCenter.default.addObserver(forName: .videoPrefetcherDidCacheAsset, object: nil, queue: .main) { note in
                if let id = note.userInfo?["id"] as? String {
                    readyVideoIDs.insert(id)
                }
            }
            NotificationCenter.default.addObserver(forName: .videoPlaybackItemReady, object: nil, queue: .main) { note in
                if let id = note.userInfo?["id"] as? String {
                    readyVideoIDs.insert(id)
                }
            }
        }
        .onDisappear {
            viewModel.configureAudioSession(active: false)
            NotificationCenter.default.removeObserver(self, name: .videoPrefetcherDidCacheAsset, object: nil)
            NotificationCenter.default.removeObserver(self, name: .videoPlaybackItemReady, object: nil)
        }
        .onChange(of: viewModel.items.map(\.id)) { _ in
            let currentVideoIDs = Set(viewModel.items.compactMap { item in
                if case .video(let a) = item.kind { return a.localIdentifier }
                return nil
            })
            readyVideoIDs.formIntersection(currentVideoIDs)

            guard !didSetInitialIndex, !viewModel.items.isEmpty else {
                if !viewModel.items.isEmpty {
                    let sizePts = UIScreen.main.bounds.size
                    prefetchWindow(around: index, sizePx: sizePts)
                }
                return
            }
            let startIndex = viewModel.initialIndexInWindow ?? 0
            index = max(0, min(viewModel.items.count - 1, startIndex))
            didSetInitialIndex = true
            Diagnostics.log("TikTokFeed initial local start index=\(index)")
            let sizePts = UIScreen.main.bounds.size
            prefetchWindow(around: index, sizePx: sizePts)
        }
        .onChange(of: scenePhase) { phase in
            Diagnostics.log("TikTokFeedView scenePhase=\(String(describing: phase))")
            if phase == .active, let url = pendingShareURL {
                Diagnostics.log("Share: presenting deferred sheet url=\(url.lastPathComponent)")
                shareItems = [url]
                shareTempURLs = [url]
                isSharing = true
                pendingShareURL = nil
            }
        }
        .onChange(of: index) { newIndex in
            let items = viewModel.items
            if items.indices.contains(newIndex) {
                if case .video(let asset) = items[newIndex].kind {
                    CurrentPlayback.shared.currentAssetID = asset.localIdentifier
                } else {
                    CurrentPlayback.shared.currentAssetID = nil
                }
            }
            viewModel.loadMoreIfNeeded(currentIndex: newIndex)
            let sizePts = UIScreen.main.bounds.size
            prefetchWindow(around: newIndex, sizePx: sizePts)
            preheatActiveCarouselIfAny(at: newIndex)
        }
        .systemShareSheet(isPresented: $isSharing, items: shareItems) { _, _, _, _ in
            for url in shareTempURLs {
                try? FileManager.default.removeItem(at: url)
            }
            shareTempURLs.removeAll()
            shareItems.removeAll()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(appleMusic: appleMusic)
        }
        .confirmationDialog("Go to", isPresented: $showDateActions, titleVisibility: .visible) {
            Button("Newest") {
                didSetInitialIndex = false
                viewModel.startFromBeginning()
            }
            Button("Random place") {
                didSetInitialIndex = false
                viewModel.loadRandomWindow()
            }
            Button("1 year ago") {
                didSetInitialIndex = false
                viewModel.jumpToOneYearAgo()
            }
            Button("Cancel", role: .cancel) { }
        }
        .overlay {
            if isQuickPanelExpanded {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        Color.black.opacity(0.20)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)

                        let panelWidth = min(proxy.size.width - 24, 380)
                        let panelHeight = min(max(proxy.size.height * 0.32, 240), 420)
                        let expandedCorner: CGFloat = 22

                        VStack(spacing: 0) {
                            QuickPanelContent()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(16)
                                .transition(.opacity)
                        }
                        .frame(width: panelWidth, height: panelHeight)
                        .background(
                            RoundedRectangle(cornerRadius: expandedCorner, style: .continuous)
                                .fill(Color(red: 0.07, green: 0.08, blue: 0.09).opacity(0.36))
                                .liquidGlass(in: RoundedRectangle(cornerRadius: expandedCorner, style: .continuous), stroke: false)
                                .matchedGeometryEffect(id: "quickGlassBG", in: quickGlassNS)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: expandedCorner, style: .continuous))
                        .onTapGesture {
                            var t = Transaction()
                            t.animation = .spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)
                            withTransaction(t) {
                                isQuickPanelExpanded = false
                            }
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 8)
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                    }
                }
                .transition(.opacity)
                .zIndex(3)
            }
        }
    }

    private func handlePrefetch(indices: IndexSet, size: CGSize) {
        guard !viewModel.items.isEmpty else { return }
        var videoAssets: [PHAsset] = []
        var photoAssetsFlat: [PHAsset] = []
        let sorted = indices.sorted()
        for i in sorted {
            guard viewModel.items.indices.contains(i) else { continue }
            switch viewModel.items[i].kind {
            case .video(let a):
                videoAssets.append(a)
            case .photoCarousel(let list):
                if FeatureFlags.enablePhotoPosts {
                    photoAssetsFlat.append(contentsOf: list)
                }
            }
        }
        if !videoAssets.isEmpty {
            Diagnostics.log("MixedFeed prefetch videos count=\(videoAssets.count) indices=\(sorted)")
            VideoPrefetcher.shared.prefetch(videoAssets)
        }
        if FeatureFlags.enablePhotoPosts, !photoAssetsFlat.isEmpty {
            let viewportPx = UIScreen.main.nativeBounds.size
            let photoPx = photoTargetSizePx(for: viewportPx)

            var primary: [PHAsset] = []
            var secondary: [PHAsset] = []
            var seen = Set<String>()

            if let firstCarouselIndex = sorted.first(where: { idx in
                guard viewModel.items.indices.contains(idx) else { return false }
                if case .photoCarousel = viewModel.items[idx].kind { return true }
                return false
            }) {
                if case .photoCarousel(let firstList) = viewModel.items[firstCarouselIndex].kind {
                    for a in firstList where seen.insert(a.localIdentifier).inserted {
                        primary.append(a)
                    }
                }
            }
            for i in sorted {
                guard viewModel.items.indices.contains(i) else { continue }
                if case .photoCarousel(let list) = viewModel.items[i].kind {
                    for a in list where seen.insert(a.localIdentifier).inserted {
                        secondary.append(a)
                    }
                }
            }

            let primaryCap = 18
            let totalCap = 48
            if primary.count > primaryCap { primary = Array(primary.prefix(primaryCap)) }
            var remainderBudget = max(0, totalCap - primary.count)
            if secondary.count > remainderBudget { secondary = Array(secondary.prefix(remainderBudget)) }

            if !primary.isEmpty {
                Diagnostics.log("MixedFeed preheat photos PRIMARY count=\(primary.count) indices=\(sorted) photoTargetSize=\(Int(photoPx.width))x\(Int(photoPx.height))")
                ImagePrefetcher.shared.preheat(primary, targetSize: photoPx)

                let deepCount = min(6, primary.count)
                if deepCount > 0 {
                    let deepPx = scaledSize(photoPx, factor: 1.6)
                    let deep = Array(primary.prefix(deepCount))
                    Diagnostics.log("MixedFeed preheat photos PRIMARY-DEEP count=\(deep.count) photoTargetSize=\(Int(deepPx.width))x\(Int(deepPx.height))")
                    ImagePrefetcher.shared.preheat(deep, targetSize: deepPx)
                }
            }
            if !secondary.isEmpty {
                Diagnostics.log("MixedFeed preheat photos SECONDARY count=\(secondary.count) indices=\(sorted) photoTargetSize=\(Int(photoPx.width))x\(Int(photoPx.height))")
                ImagePrefetcher.shared.preheat(secondary, targetSize: photoPx)
            }
        }
    }
    
    private func handleCancelPrefetch(indices: IndexSet, size: CGSize) {
        guard !viewModel.items.isEmpty else { return }
        var videoAssets: [PHAsset] = []
        var photoAssets: [PHAsset] = []
        for i in indices {
            guard viewModel.items.indices.contains(i) else { continue }
            switch viewModel.items[i].kind {
            case .video(let a):
                videoAssets.append(a)
            case .photoCarousel(let list):
                if FeatureFlags.enablePhotoPosts {
                    photoAssets.append(contentsOf: list)
                }
            }
        }
        if !videoAssets.isEmpty {
            Diagnostics.log("MixedFeed cancel prefetch videos count=\(videoAssets.count) indices=\(Array(indices))")
            VideoPrefetcher.shared.cancel(videoAssets)
        }
        if FeatureFlags.enablePhotoPosts, !photoAssets.isEmpty {
            let viewportPx = UIScreen.main.nativeBounds.size
            let photoPx = photoTargetSizePx(for: viewportPx)
            Diagnostics.log("MixedFeed stop preheating photos count=\(photoAssets.count) indices=\(Array(indices)) photoTargetSize=\(Int(photoPx.width))x\(Int(photoPx.height))")
            ImagePrefetcher.shared.stopPreheating(photoAssets, targetSize: photoPx)
        }
    }
    
    private func prefetchWindow(around index: Int, sizePx: CGSize) {
        let lookahead = 10
        let start = max(0, index)
        let end = min(viewModel.items.count, index + 1 + lookahead)
        guard start < end else { return }
        let candidates = Array(start..<end)
        handlePrefetch(indices: IndexSet(candidates), size: sizePx)
    }

    private func preheatActiveCarouselIfAny(at index: Int) {
        if !FeatureFlags.enablePhotoPosts { return }
        guard viewModel.items.indices.contains(index) else { return }
        guard case .photoCarousel(let list) = viewModel.items[index].kind else { return }
        guard !list.isEmpty else { return }
        let viewportPx = UIScreen.main.nativeBounds.size
        let photoPx = photoTargetSizePx(for: viewportPx)
        Diagnostics.log("MixedFeed preheat ACTIVE carousel count=\(list.count) photoTargetSize=\(Int(photoPx.width))x\(Int(photoPx.height))")
        ImagePrefetcher.shared.preheat(list, targetSize: photoPx)
        let deepCount = min(6, list.count)
        if deepCount > 0 {
            let deepPx = scaledSize(photoPx, factor: 1.6)
            let deep = Array(list.prefix(deepCount))
            Diagnostics.log("MixedFeed preheat ACTIVE-DEEP count=\(deep.count) photoTargetSize=\(Int(deepPx.width))x\(Int(deepPx.height))")
            ImagePrefetcher.shared.preheat(deep, targetSize: deepPx)
        }
    }
    
    private func photoTargetSizePx(for viewportPx: CGSize) -> CGSize {
        let isLandscape = viewportPx.width > viewportPx.height
        let columns: CGFloat = isLandscape ? 4 : 3
        let cell = floor(min(viewportPx.width, viewportPx.height) / columns)
        let edge = max(160, min(cell, 512))
        return CGSize(width: edge, height: edge)
    }

    private func scaledSize(_ size: CGSize, factor: CGFloat) -> CGSize {
        CGSize(width: floor(size.width * factor), height: floor(size.height * factor))
    }
    
    private var deniedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Photos access needed")
                .font(.headline)
            Text("To browse your recent videos and photos, allow Photos access in Settings.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            HStack(spacing: 16) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "film")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No media found")
                .font(.headline)
            Text("Record or import some videos or photos to your Photos library.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }
    
    private func currentVideoAsset() -> PHAsset? {
        guard viewModel.items.indices.contains(index) else { return nil }
        if case .video(let a) = viewModel.items[index].kind {
            return a
        }
        return nil
    }
    
    private func dateLabelForCurrentItem() -> String? {
        guard viewModel.items.indices.contains(index) else { return nil }
        switch viewModel.items[index].kind {
        case .video(let a):
            if let d = a.creationDate {
                return Self.dateFormatter.string(from: d)
            }
            return nil
        case .photoCarousel(let assets):
            let dates = assets.compactMap(\.creationDate)
            guard let minD = dates.min() else { return nil }
            guard let maxD = dates.max() else { return Self.dateFormatter.string(from: minD) }
            if Calendar.current.isDate(minD, inSameDayAs: maxD) {
                return Self.dateFormatter.string(from: minD)
            } else {
                let minStr = Self.dateFormatter.string(from: minD)
                let maxStr = Self.dateFormatter.string(from: maxD)
                return "\(minStr) – \(maxStr)"
            }
        }
    }

    private func relativeLabelForCurrentItem() -> String? {
        guard viewModel.items.indices.contains(index) else { return nil }
        let now = Date()
        switch viewModel.items[index].kind {
        case .video(let a):
            if let d = a.creationDate {
                return Self.relativeFormatter.localizedString(for: d, relativeTo: now)
            }
            return nil
        case .photoCarousel(let assets):
            let dates = assets.compactMap(\.creationDate)
            guard let maxD = dates.max() else { return nil }
            return Self.relativeFormatter.localizedString(for: maxD, relativeTo: now)
        }
    }
    
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let rf = RelativeDateTimeFormatter()
        rf.unitsStyle = .full
        return rf
    }()
    
    private func prepareShare() {
        guard !isPreparingShare, let asset = currentVideoAsset() else { return }
        isPreparingShare = true
        Diagnostics.log("Share: start export id=\(asset.localIdentifier)")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task(priority: .userInitiated) {
            do {
                let url = try await PHAsset.exportVideoToTempURL(asset)
                Diagnostics.log("Share: export finished url=\(url.lastPathComponent)")
                if UIApplication.shared.applicationState == .active {
                    await MainActor.run {
                        shareItems = [url]
                        shareTempURLs = [url]
                        isSharing = true
                        isPreparingShare = false
                    }
                } else {
                    await MainActor.run {
                        pendingShareURL = url
                        isPreparingShare = false
                        Diagnostics.log("Share: deferred presentation (app not active)")
                    }
                }
            } catch {
                await MainActor.run {
                    isPreparingShare = false
                }
                Diagnostics.log("Share: export failed error=\(String(describing: error))")
            }
        }
    }

    private func deleteCurrentVideo() {
        guard let asset = currentVideoAsset() else { return }
        let id = asset.localIdentifier
        Diagnostics.log("Delete video: hide id=\(id)")
        Task { @MainActor in
            await DeletedVideosStore.shared.hide(id: id)
            await PlaybackPositionStore.shared.clear(id: id)
            VideoPrefetcher.shared.removeCached(for: [id])
            if let idx = viewModel.items.firstIndex(where: { item in
                if case .video(let a) = item.kind { return a.localIdentifier == id }
                return false
            }) {
                viewModel.items.remove(at: idx)
                if index >= viewModel.items.count {
                    index = max(0, viewModel.items.count - 1)
                }
            }
        }
    }

    private func shareURL(for asset: PHAsset) async -> URL? {
        do {
            let url = try await PHAsset.exportVideoToTempURL(asset)
            return url
        } catch {
            return nil
        }
    }

    private struct QuickPanelContent: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Quick Panel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 44)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 44)
                Spacer(minLength: 0)
            }
        }
    }
}