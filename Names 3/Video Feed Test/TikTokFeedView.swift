import SwiftUI
import Photos
import UIKit
import Combine
import MediaPlayer

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
    @Namespace private var dateGlassNS
    @State private var isMusicSearchPresented = false

    @State private var firstCellFrameObserver: NSObjectProtocol?
    @State private var didShowFirstFrame = false
    @State private var criticalPrefetchedIDs: Set<String> = []
    @State private var pendingScrollToAssetID: String?
    @State private var pendingScrollLoadInFlight = false  // Avoid loop when carousel asset not in Feed (e.g. photo-only)

    private struct CellMountLogger: View {
        let idx: Int
        let id: String
        let isActive: Bool
        let kind: String
        var body: some View {
            Color.clear
                .onAppear {
                    Diagnostics.log("Page mount idx=\(idx) id=\(id) kind=\(kind) isActive=\(isActive)")
                }
                .onDisappear {
                    Diagnostics.log("Page unmount idx=\(idx) id=\(id) kind=\(kind)")
                }
        }
    }

    private func pageIsReady(_ idx: Int) -> Bool {
        guard viewModel.items.indices.contains(idx) else {
            Diagnostics.log("PageReady idx=\(idx) -> true (out of range)")
            return true
        }
        switch viewModel.items[idx].kind {
        case .video(let a):
            let ready = readyVideoIDs.contains(a.localIdentifier)
            if idx == index || idx < 3 {
                Diagnostics.log("PageReady idx=\(idx) video=\(a.localIdentifier) ready=\(ready) currentIdx=\(index) readySetCount=\(readyVideoIDs.count)")
            }
            return ready
        case .photoCarousel:
            if idx == index || idx < 3 {
                Diagnostics.log("PageReady idx=\(idx) carousel -> true")
            }
            return true
        }
    }

    /// When set, syncs position with Carousel and reports current asset for morph transition.
    var coordinator: CombinedMediaCoordinator?

    /// When false (carousel visible), feed pauses shared player; when true, feed consumes bridge on becoming visible.
    var isFeedVisible: Bool = true

    init(mode: TikTokFeedViewModel.FeedMode = .explore, coordinator: CombinedMediaCoordinator? = nil, isFeedVisible: Bool = true) {
        _viewModel = StateObject(wrappedValue: TikTokFeedViewModel(mode: mode))
        self.coordinator = coordinator
        self.isFeedVisible = isFeedVisible
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
                                    initialIndex: !didSetInitialIndex ? viewModel.initialIndexInWindow : nil,
                                    id: { $0.id },
                                    onPrefetch: handlePrefetch(indices:size:),
                                    onCancelPrefetch: handleCancelPrefetch(indices:size:),
                                    isPageReady: { (idx: Int) in
                    pageIsReady(idx)
                },
                                    content: { i, item, isActive in
                    switch item.kind {
                    case .video(let asset):
                        AnyView(
                            TikTokPlayerView(
                                asset: asset,
                                isActive: isActive && isFeedVisible,
                                pinnedMode: options.progress > 0.001,
                                noCropMode: true,
                                sharedController: coordinator?.sharedVideoPlayer
                            )
                            .id(item.id)
                            .optionsPinnedTopTransform(progress: options.progress)
                            .animation(options.isInteracting ? nil : .interpolatingSpring(stiffness: 220, damping: 28), value: options.progress)
                            .background(
                                CellMountLogger(idx: i, id: item.id, isActive: isActive, kind: "video")
                                    .allowsHitTesting(false)
                            )
                        )
                    case .photoCarousel(let assets):
                        if FeatureFlags.enablePhotoPosts || !assets.isEmpty {
                            AnyView(
                                PhotoCarouselPostView(assets: assets)
                                    .id(item.id)
                                    .background(
                                        CellMountLogger(idx: i, id: item.id, isActive: isActive, kind: "carousel")
                                            .allowsHitTesting(false)
                                    )
                            )
                        } else {
                            AnyView(
                                EmptyView()
                                    .id(item.id)
                                    .background(
                                        CellMountLogger(idx: i, id: item.id, isActive: isActive, kind: "empty")
                                            .allowsHitTesting(false)
                                    )
                            )
                        }
                    }
                },
                                    onScrollInteracting: { interacting in
                    isPagingInteracting = interacting
                    Diagnostics.log("PagedCollection interacting=\(interacting)")
                })
                .background(
                    Color.clear
                        .onAppear {
                            Diagnostics.log("Feed branch: PagedCollection appeared")
                        }
                )
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    OptionsSheet(
                        options: options,
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
                            Button {
                                var t = Transaction()
                                t.animation = .spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)
                                withTransaction(t) {
                                    showDateActions = true
                                }
                            } label: {
                                let collapsedCorner: CGFloat = 24
                                HStack(alignment: .center, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if let rel = relativeLabelForCurrentItem() {
                                            Text(rel)
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule().fill(Color.white.opacity(0.06))
                                                )
                                                .accessibilityHidden(true)
                                        }
                                        if let dur = videoDurationLabelForCurrentItem() {
                                            Text(dur)
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule().fill(Color.white.opacity(0.06))
                                                )
                                                .accessibilityHidden(true)
                                        }
                                        if let size = videoFileSizeLabelForCurrentItem() {
                                            let label: String = {
                                                if let tag = assetShortTagForCurrentItem() {
                                                    return "\(size) · \(tag)"
                                                } else {
                                                    return size
                                                }
                                            }()
                                            Text(label)
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule().fill(Color.white.opacity(0.06))
                                                )
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    if let label = dateLabelForCurrentItem() {
                                        Text(label)
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule().fill(Color.white.opacity(0.06))
                                            )
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: collapsedCorner, style: .continuous)
                                        .fill(Color.black.opacity(0.28))
                                        .liquidGlass(in: RoundedRectangle(cornerRadius: collapsedCorner, style: .continuous), stroke: false)
                                        .matchedGeometryEffect(id: "dateGlassBG", in: dateGlassNS)
                                )
                                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 12)
                            .accessibilityLabel("Go to date")
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
        .onChange(of: isFeedVisible) { _, nowVisible in
            // When switching Carousel→Feed: feed becomes visible but doesn't get onAppear (always mounted).
            // Consume bridge here so we scroll to the carousel's asset.
            guard nowVisible, let coord = coordinator else { return }
            let bridgeID = coord.consumeBridgeTarget()
            if let id = bridgeID {
                didSetInitialIndex = false  // Allow items onChange to apply bridge index (was blocking when feed pre-loaded)
                pendingScrollToAssetID = id
                viewModel.initialBridgeAssetID = id
                Diagnostics.log("[Bridge] Feed became visible: scroll to Carousel asset \(id)")
                applyPendingScrollIfNeeded()
                if viewModel.items.isEmpty || viewModel.indexOfAsset(id: id) == nil {
                    pendingScrollLoadInFlight = true
                    viewModel.loadWindowContaining(assetID: id)
                } else {
                    pendingScrollLoadInFlight = false
                }
            }
        }
        .onAppear {
            // Single source: consume bridge target from coordinator (Carousel→Feed handoff, first load)
            let bridgeID = coordinator?.consumeBridgeTarget()
            // #region agent log
            Diagnostics.debugBridge(hypothesisId: "B", location: "TikTokFeedView.onAppear", message: "Feed onAppear: bridge ID", data: ["bridgeID": bridgeID ?? "nil"])
            // #endregion
            if let id = bridgeID {
                pendingScrollToAssetID = id
                pendingScrollLoadInFlight = false
                viewModel.initialBridgeAssetID = id
                Diagnostics.log("[Bridge] Feed will load window for Carousel asset \(id)")
            }
            let appState = UIApplication.shared.applicationState
            BootTimeline.mark("TikTokFeed onAppear")
            Diagnostics.log("TikTokFeed onAppear appState=\(appState.rawValue) scenePhase=\(String(describing: scenePhase))")
            Diagnostics.log("StartWindow: items=\(viewModel.items.count) auth=\(String(describing: viewModel.authorization)) isLoading=\(viewModel.isLoading)")
            FirstLaunchProbe.shared.feedAppear()

            BootUIMetrics.shared.beginFirstFrameToFirstCell()
            BootUIMetrics.shared.beginFirstFrameToFirstCellMounted()

            if firstCellFrameObserver == nil {
                firstCellFrameObserver = NotificationCenter.default.addObserver(forName: .playerFirstFrameDisplayed, object: nil, queue: .main) { _ in
                    BootUIMetrics.shared.endFirstFrameToFirstCell()
                    didShowFirstFrame = true
                    criticalPrefetchedIDs.removeAll()
                    let sizePts = UIScreen.main.bounds.size
                    Diagnostics.log("FirstFrame: gate lifted → trigger prefetch window around idx=\(index)")
                    prefetchWindow(around: index, sizePx: sizePts)
                    preheatActiveCarouselIfAny(at: index)
                    if let obs = firstCellFrameObserver {
                        NotificationCenter.default.removeObserver(obs)
                        firstCellFrameObserver = nil
                    }
                }
            }

            Task { @MainActor in
                for i in 0..<8 {
                    try? await Task.sleep(for: .milliseconds(500))
                    Diagnostics.log("FeedProbe t=\(i) auth=\(String(describing: viewModel.authorization)) isLoading=\(viewModel.isLoading) items=\(viewModel.items.count) index=\(index)")
                }
            }
            viewModel.onAppear()
            NotificationCenter.default.addObserver(forName: .videoPrefetcherDidCacheAsset, object: nil, queue: .main) { note in
                if let id = note.userInfo?["id"] as? String {
                    readyVideoIDs.insert(id)
                    Diagnostics.log("ReadyIDs +cache id=\(id) count=\(readyVideoIDs.count) currentIdx=\(index)")
                }
            }
            NotificationCenter.default.addObserver(forName: .videoPlaybackItemReady, object: nil, queue: .main) { note in
                if let id = note.userInfo?["id"] as? String {
                    readyVideoIDs.insert(id)
                    Diagnostics.log("ReadyIDs +ready id=\(id) count=\(readyVideoIDs.count) currentIdx=\(index)")
                }
            }

            #if DEBUG
            RunLoopDriftMonitor.shared.start()
            #endif
        }
        .onDisappear {
            viewModel.configureAudioSession(active: false)
            if let obs = firstCellFrameObserver {
                NotificationCenter.default.removeObserver(obs)
                firstCellFrameObserver = nil
            }
            NotificationCenter.default.removeObserver(self, name: .videoPrefetcherDidCacheAsset, object: nil)
            NotificationCenter.default.removeObserver(self, name: .videoPlaybackItemReady, object: nil)
            criticalPrefetchedIDs.removeAll()
            #if DEBUG
            RunLoopDriftMonitor.shared.stop()
            #endif
        }
        .onChange(of: viewModel.isLoading) { _, newVal in
            Diagnostics.log("Feed isLoading=\(newVal)")
        }
        .onChange(of: viewModel.items.map(\.id)) { _, _ in
            let currentVideoIDs = Set(viewModel.items.compactMap { item in
                if case .video(let a) = item.kind { return a.localIdentifier }
                return nil
            })
            readyVideoIDs.formIntersection(currentVideoIDs)
            Diagnostics.log("Feed items changed -> count=\(viewModel.items.count) readyVideos=\(readyVideoIDs.count)")

            guard !didSetInitialIndex, !viewModel.items.isEmpty else {
                if !viewModel.items.isEmpty {
                    let sizePts = UIScreen.main.bounds.size
                    Diagnostics.log("PrefetchWindow reuse around idx=\(index)")
                    prefetchWindow(around: index, sizePx: sizePts)
                }
                return
            }
            let startIndex: Int
            if let pendingID = pendingScrollToAssetID {
                let idx = viewModel.indexOfAsset(id: pendingID)
                // #region agent log
                Diagnostics.debugBridge(hypothesisId: "F", location: "TikTokFeedView.itemsOnChange", message: "resolving startIndex", data: ["pendingID": pendingID, "indexOfAsset": idx?.description ?? "nil", "itemsCount": viewModel.items.count, "initialIndexInWindow": viewModel.initialIndexInWindow?.description ?? "nil"])
                // #endregion
                if let idx = idx {
                    startIndex = idx
                    pendingScrollToAssetID = nil
                    pendingScrollLoadInFlight = false
                } else if pendingScrollLoadInFlight {
                    // loadWindowContaining already ran; asset not in Feed structure (e.g. photo-only). Use best-effort index.
                    Diagnostics.log("Feed: bridge asset \(pendingID) not in Feed items, using initialIndexInWindow=\(viewModel.initialIndexInWindow ?? 0)")
                    startIndex = viewModel.initialIndexInWindow ?? 0
                    pendingScrollToAssetID = nil
                    pendingScrollLoadInFlight = false
                } else {
                    Diagnostics.log("Feed: asset \(pendingID) not in current items, loading window containing it")
                    didSetInitialIndex = false
                    pendingScrollLoadInFlight = true
                    viewModel.loadWindowContaining(assetID: pendingID)
                    return
                }
            } else {
                startIndex = viewModel.initialIndexInWindow ?? 0
            }
            // PagedCollectionView owns index during bridge (initialIndex); we set it here as fallback for non-bridge
            let clamped = max(0, min(viewModel.items.count - 1, startIndex))
            index = clamped
            didSetInitialIndex = true
            Diagnostics.log("TikTokFeed initial local start index=\(clamped)")
            if viewModel.items.indices.contains(index), case .video(let a) = viewModel.items[index].kind {
                Task { await NextVideoTraceCenter.shared.begin(assetID: a.localIdentifier, idx: index, total: viewModel.items.count) }
            }
            let sizePts = UIScreen.main.bounds.size
            prefetchWindow(around: index, sizePx: sizePts)
            preheatActiveCarouselIfAny(at: index)
        }
        .onChange(of: didShowFirstFrame) { _, newVal in
            guard newVal else { return }
            let sizePts = UIScreen.main.bounds.size
            Diagnostics.log("FirstFrame(onChange): trigger prefetch window around idx=\(index)")
            prefetchWindow(around: index, sizePx: sizePts)
            preheatActiveCarouselIfAny(at: index)
        }
        .onChange(of: scenePhase) { _, phase in
            Diagnostics.log("TikTokFeedView scenePhase=\(String(describing: phase)) appState=\(UIApplication.shared.applicationState.rawValue)")
            if phase == .active, let url = pendingShareURL {
                Diagnostics.log("Share: presenting deferred sheet url=\(url.lastPathComponent)")
                shareItems = [url]
                shareTempURLs = [url]
                isSharing = true
                pendingShareURL = nil
            }
        }
        .onChange(of: index) { _, newIndex in
            if viewModel.initialIndexInWindow != nil { didSetInitialIndex = true }
            Diagnostics.log("Feed index=\(newIndex)")
            let items = viewModel.items
            if items.indices.contains(newIndex) {
                let assetID = currentAssetID()
                if case .video = items[newIndex].kind {
                    CurrentPlayback.shared.currentAssetID = assetID
                    Task { await NextVideoTraceCenter.shared.begin(assetID: assetID ?? "", idx: newIndex, total: items.count) }
                } else {
                    CurrentPlayback.shared.currentAssetID = nil
                }
                coordinator?.currentAssetID = assetID
            }
            viewModel.loadMoreIfNeeded(currentIndex: newIndex)
            let sizePts = UIScreen.main.bounds.size
            prefetchWindow(around: newIndex, sizePx: sizePts)
            preheatActiveCarouselIfAny(at: newIndex)
        }
        .onAppear {
            // Only update coordinator when we have a valid asset to report (don't overwrite carousel's value with nil when Feed is still loading)
            if let coord = coordinator, let id = currentAssetID() {
                coord.currentAssetID = id
            }
            applyPendingScrollIfNeeded()
        }
        .onChange(of: viewModel.items.count) { _, _ in
            applyPendingScrollIfNeeded()
        }
        .onChange(of: isQuickPanelExpanded) { _, expanded in
            guard expanded, FeatureFlags.enableAppleMusicIntegration else { return }
            Task {
                Diagnostics.log("QuickPanel: expanded -> bootstrap Apple Music")
                await MusicBootstrapper.shared.ensureBootstrapped()
                await MainActor.run {
                    MusicCenter.shared.attachIfNeeded()
                    appleMusic.bootstrap()
                }
            }
        }
        .systemShareSheet(isPresented: $isSharing, items: shareItems) { _, _, _, _ in
            for url in shareTempURLs {
                try? FileManager.default.removeItem(at: url)
            }
            shareTempURLs.removeAll()
            shareItems.removeAll()
        }
        .sheet(isPresented: $showSettings) {
            VideoFeedSettingsView(appleMusic: appleMusic)
        }
        .overlay {
            if isQuickPanelExpanded {
                QuickPanelOverlayView(
                    isQuickPanelExpanded: $isQuickPanelExpanded,
                    appleMusic: appleMusic,
                    currentAssetID: currentVideoAsset()?.localIdentifier,
                    quickGlassNS: quickGlassNS,
                    isMusicSearchPresented: $isMusicSearchPresented
                )
                .transition(.opacity)
                .zIndex(3)
            }
        }
        .overlay {
            if showDateActions {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomLeading) {
                        Color.black.opacity(0.20)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)

                        let panelWidth = min(proxy.size.width - 24, 380)
                        let panelHeight = min(max(proxy.size.height * 0.26, 200), 320)
                        let expandedCorner: CGFloat = 22

                        VStack(spacing: 0) {
                            DateGoToPanel(
                                onClose: {
                                    var t = Transaction()
                                    t.animation = .spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)
                                    withTransaction(t) {
                                        showDateActions = false
                                    }
                                },
                                onNewest: {
                                    didSetInitialIndex = false
                                    viewModel.startFromBeginning()
                                    showDateActions = false
                                },
                                onRandom: {
                                    didSetInitialIndex = false
                                    viewModel.loadRandomWindow()
                                    showDateActions = false
                                },
                                onYearAgo: {
                                    didSetInitialIndex = false
                                    viewModel.jumpToOneYearAgo()
                                    showDateActions = false
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(16)
                            .transition(.opacity)
                        }
                        .frame(width: panelWidth, height: panelHeight)
                        .background(
                            RoundedRectangle(cornerRadius: expandedCorner, style: .continuous)
                                .fill(Color(red: 0.07, green: 0.08, blue: 0.09).opacity(0.36))
                                .liquidGlass(in: RoundedRectangle(cornerRadius: expandedCorner, style: .continuous), stroke: false)
                                .matchedGeometryEffect(id: "dateGlassBG", in: dateGlassNS)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: expandedCorner, style: .continuous))
                        .onTapGesture {
                            var t = Transaction()
                            t.animation = .spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)
                            withTransaction(t) {
                                showDateActions = false
                            }
                        }
                        .padding(.leading, 12)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 8)
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
                    }
                }
                .transition(.opacity)
                .zIndex(4)
            }
        }
        .fullScreenCover(isPresented: $isMusicSearchPresented) {
            AppleMusicSearchScreen(assetID: currentVideoAsset()?.localIdentifier) {
                isMusicSearchPresented = false
            }
        }
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

    /// Current asset ID (video or first photo of carousel) for coordinator sync.
    private func currentAssetID() -> String? {
        guard viewModel.items.indices.contains(index) else { return nil }
        switch viewModel.items[index].kind {
        case .video(let a): return a.localIdentifier
        case .photoCarousel(let arr): return arr.first?.localIdentifier
        }
    }

    private func applyPendingScrollIfNeeded() {
        guard let id = pendingScrollToAssetID, !viewModel.items.isEmpty,
              let idx = viewModel.indexOfAsset(id: id), idx != index else { return }
        pendingScrollToAssetID = nil
        index = idx
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
                return Self.friendlyRelativeString(for: d, now: now)
            }
            return nil
        case .photoCarousel(let assets):
            let dates = assets.compactMap(\.creationDate)
            guard let maxD = dates.max() else { return nil }
            return Self.friendlyRelativeString(for: maxD, now: now)
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

    private static let isoCal: Calendar = {
        var c = Calendar(identifier: .iso8601)
        return c
    }()

    private static func startOfISOWeek(for date: Date) -> Date {
        if let interval = isoCal.dateInterval(of: .weekOfYear, for: date) {
            return interval.start
        }
        return date
    }

    private static func friendlyRelativeString(for date: Date, now: Date = Date()) -> String {
        let f = Self.relativeFormatter
        let cal = Calendar.current

        let absSeconds = abs(date.timeIntervalSince(now))
        if absSeconds < 24 * 60 * 60 {
            return f.localizedString(for: date, relativeTo: now)
        }

        let startA = cal.startOfDay(for: date)
        let startB = cal.startOfDay(for: now)
        let inPast = startA <= startB
        let dayDelta = abs(cal.dateComponents([.day], from: startA, to: startB).day ?? Int(absSeconds / (24 * 60 * 60)))

        if dayDelta < 7 {
            let signed = inPast ? -dayDelta : dayDelta
            return f.localizedString(from: DateComponents(day: signed))
        }

        // Years handling with rounding, and a single 18-months exception
        let totalMonths = abs(cal.dateComponents([.month], from: startA, to: startB).month ?? 0)
        if totalMonths >= 12 {
            if totalMonths == 18 {
                let yearsStr = plural(1, "year")
                let monthsStr = plural(6, "month")
                return inPast ? "\(yearsStr) \(monthsStr) ago" : "in \(yearsStr) \(monthsStr)"
            }
            let roundedYears = max(1, Int((Double(totalMonths) / 12.0).rounded()))
            let signedYears = inPast ? -roundedYears : roundedYears
            return f.localizedString(from: DateComponents(year: signedYears))
        }

        // Sub-year: weeks or months
        let isoA = startOfISOWeek(for: startA)
        let isoB = startOfISOWeek(for: startB)
        let weeksDelta = abs(isoCal.dateComponents([.weekOfYear], from: isoA, to: isoB).weekOfYear ?? max(1, dayDelta / 7))

        if weeksDelta >= 12 {
            let monthsDelta = max(1, totalMonths)
            let signedMonths = inPast ? -monthsDelta : monthsDelta
            return f.localizedString(from: DateComponents(month: signedMonths))
        }

        let signedWeeks = inPast ? -weeksDelta : weeksDelta
        return f.localizedString(from: DateComponents(weekOfMonth: signedWeeks))
    }

    private static func plural(_ value: Int, _ unit: String) -> String {
        value == 1 ? "\(value) \(unit)" : "\(value) \(unit)s"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f
    }()

    private func handlePrefetch(indices: IndexSet, size: CGSize) {
        guard !viewModel.items.isEmpty else { return }

        let criticalWindow = !didShowFirstFrame || UIApplication.shared.applicationState != .active

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
            if criticalWindow {
                var primary: [PHAsset] = []
                for i in sorted {
                    guard viewModel.items.indices.contains(i) else { continue }
                    if i == index, case .video(let a) = viewModel.items[i].kind {
                        primary.append(a)
                    }
                }
                if primary.isEmpty {
                    Diagnostics.log("MixedFeed prefetch videos SKIP (critical window) indices=\(sorted)")
                } else {
                    Diagnostics.log("MixedFeed prefetch CURRENT video (critical window-bypass) count=\(primary.count) idx=\(index)")
                    if let firstID = FirstLaunchProbe.shared.firstAssetID {
                        let ids = Set(primary.map { $0.localIdentifier })
                        if ids.contains(firstID) {
                            FirstLaunchProbe.shared.prefetchCall(id: firstID)
                        }
                    }
                    VideoPrefetcher.shared.prefetch(primary)
                    PlayerItemPrefetcher.shared.prefetch(primary)
                }
            } else {
                Diagnostics.log("MixedFeed prefetch videos count=\(videoAssets.count) indices=\(sorted)")
                if let firstID = FirstLaunchProbe.shared.firstAssetID {
                    let ids = Set(videoAssets.map { $0.localIdentifier })
                    if ids.contains(firstID) {
                        FirstLaunchProbe.shared.prefetchCall(id: firstID)
                    }
                }
                VideoPrefetcher.shared.prefetch(videoAssets)
                PlayerItemPrefetcher.shared.prefetch(videoAssets)
            }
        }

        if FeatureFlags.enablePhotoPosts, !photoAssetsFlat.isEmpty {
            if criticalWindow {
                Diagnostics.log("MixedFeed preheat photos SKIP (critical window) indices=\(sorted)")
            } else {
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
            PlayerItemPrefetcher.shared.cancel(videoAssets)
        }
        if FeatureFlags.enablePhotoPosts, !photoAssets.isEmpty {
            let viewportPx = UIScreen.main.nativeBounds.size
            let photoPx = photoTargetSizePx(for: viewportPx)
            Diagnostics.log("MixedFeed stop preheating photos count=\(photoAssets.count) indices=\(Array(indices)) photoTargetSize=\(Int(photoPx.width))x\(Int(photoPx.height))")
            ImagePrefetcher.shared.stopPreheating(photoAssets, targetSize: photoPx)
        }
    }
    
    private func prefetchWindow(around index: Int, sizePx: CGSize) {
        let criticalWindow = !didShowFirstFrame || UIApplication.shared.applicationState != .active
        let lookahead = criticalWindow ? 1 : 10
        let start = max(0, index)
        let end = min(viewModel.items.count, index + 1 + lookahead)
        guard start < end else { return }
        let candidates = Array(start..<end)
        Task { await NextVideoTraceCenter.shared.markPrefetchWindow(currentIndex: index, window: candidates) }
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
    
    private func videoDurationLabelForCurrentItem() -> String? {
        guard viewModel.items.indices.contains(index) else { return nil }
        switch viewModel.items[index].kind {
        case .video(let a):
            return formatDuration(a.duration)
        case .photoCarousel:
            return nil
        }
    }

    private func videoFileSizeLabelForCurrentItem() -> String? {
        guard viewModel.items.indices.contains(index) else { return nil }
        switch viewModel.items[index].kind {
        case .video(let a):
            let resources = PHAssetResource.assetResources(for: a)
            let preferred = resources.first(where: { res in
                res.type == .pairedVideo || res.type == .video || res.type == .fullSizeVideo
            }) ?? resources.first
            if let preferred,
               let bytes = (preferred.value(forKey: "fileSize") as? NSNumber)?.int64Value,
               bytes > 0 {
                return Self.byteFormatter.string(fromByteCount: bytes)
            }
            return nil
        case .photoCarousel:
            return nil
        }
    }

    private func assetShortTagForCurrentItem() -> String? {
        guard viewModel.items.indices.contains(index) else { return nil }
        if case .video(let a) = viewModel.items[index].kind {
            return Diagnostics.shortTag(for: a.localIdentifier)
        }
        return nil
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }



    private struct QuickPanelOverlayView: View {
        @Binding var isQuickPanelExpanded: Bool
        @ObservedObject var appleMusic: MusicLibraryModel
        let currentAssetID: String?
        let quickGlassNS: Namespace.ID
        @Binding var isMusicSearchPresented: Bool

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    Color.black.opacity(0.20)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)

                    let panelWidth = min(proxy.size.width - 24, 380)
                    let panelHeight = min(max(proxy.size.height * 0.32, 240), 420)
                    let expandedCorner: CGFloat = 22

                    VStack(spacing: 0) {
                        QuickPanelContent(
                            appleMusic: appleMusic,
                            currentAssetID: currentAssetID,
                            isSearchPresented: $isMusicSearchPresented,
                            onClose: {
                                var t = Transaction()
                                t.animation = .spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.12)
                                withTransaction(t) {
                                    isQuickPanelExpanded = false
                                }
                            }
                        )
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
        }
    }

    private struct QuickPanelContent: View {
        @ObservedObject var appleMusic: MusicLibraryModel
        let currentAssetID: String?
        @Binding var isSearchPresented: Bool
        var onClose: () -> Void

        @ObservedObject private var music = MusicCenter.shared
        @State private var hasAssignedSong = false

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
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .liquidGlass(in: Circle(), stroke: false)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                if FeatureFlags.enableAppleMusicIntegration {
                    MusicControlsQuick(isPlaying: music.isPlaying)

                    HStack {
                        Text("Pick a song to play")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        if hasAssignedSong, currentAssetID != nil {
                            Button {
                                if let id = currentAssetID {
                                    Task { await VideoAudioOverrides.shared.setSongReference(for: id, reference: nil) }
                                    Task {
                                        AppleMusicController.shared.pauseIfManaged()
                                        AppleMusicController.shared.stopManaging()
                                    }
                                }
                            } label: {
                                Label("Remove song", systemImage: "music.note.slash")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule().fill(Color.white.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove song from this video")
                        }
                    }

                    if AppleMusicCatalog.isConfigured {
                        Button {
                            isSearchPresented = true
                        } label: {
                            Label("Search Apple Music", systemImage: "magnifyingglass")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minHeight: 44)
                                .background(
                                    Capsule().fill(Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open Apple Music search")
                    } else {
                        Text("Apple Music search unavailable: missing developer token.")
                            .foregroundStyle(.white.opacity(0.8))
                            .font(.caption)
                    }

                    if !appleMusic.catalogMatches.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(appleMusic.catalogMatches, id: \.storeID) { song in
                                    Button {
                                        if let id = currentAssetID {
                                            Task { await VideoAudioOverrides.shared.setSongReference(for: id, reference: SongReference.appleMusic(storeID: song.storeID, title: song.title, artist: song.artist)) }
                                        }
                                        Task {
                                            Diagnostics.log("QuickPanel: play catalog match -> ensureBootstrapped")
                                            await MusicBootstrapper.shared.ensureBootstrapped()
                                            AppleMusicController.shared.play(storeID: song.storeID)
                                        }
                                    } label: {
                                        HStack(alignment: .center, spacing: 10) {
                                            let size: CGFloat = 44
                                            AsyncImage(url: song.artworkURL) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image.resizable()
                                                        .scaledToFill()
                                                        .frame(width: size, height: size)
                                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                case .empty:
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(Color.white.opacity(0.06))
                                                        .frame(width: size, height: size)
                                                case .failure:
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .fill(Color.white.opacity(0.06))
                                                        .frame(width: size, height: size)
                                                        .overlay(
                                                            Image(systemName: "music.note")
                                                                .foregroundStyle(.white.opacity(0.7))
                                                        )
                                                @unknown default:
                                                    EmptyView()
                                                }
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(song.title)
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                    .font(.footnote.weight(.semibold))
                                                Text(song.artist)
                                                    .foregroundStyle(.white.opacity(0.8))
                                                    .lineLimit(1)
                                                    .font(.caption2)
                                            }
                                        }
                                        .frame(width: 220, alignment: .leading)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.white.opacity(0.06))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Group {
                        switch appleMusic.authorization {
                        case .authorized:
                            if appleMusic.isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Loading your recent songs…")
                                        .foregroundStyle(.white.opacity(0.8))
                                        .font(.footnote)
                                }
                            } else if appleMusic.lastAdded.isEmpty {
                                if appleMusic.catalogMatches.isEmpty {
                                    Text("No recent songs found in your library.")
                                        .foregroundStyle(.white.opacity(0.8))
                                        .font(.footnote)
                                }
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(appleMusic.lastAdded, id: \.persistentID) { item in
                                            Button {
                                                if let id = currentAssetID {
                                                    let storeID: String? = nil
                                                    Task { await VideoAudioOverrides.shared.setSongOverride(for: id, storeID: storeID) }
                                                }
                                                Task {
                                                    Diagnostics.log("QuickPanel: play recent item -> ensureBootstrapped")
                                                    await MusicBootstrapper.shared.ensureBootstrapped()
                                                    appleMusic.play(item)
                                                }
                                            } label: {
                                                HStack(alignment: .center, spacing: 10) {
                                                    let size: CGFloat = 44
                                                    if let img = appleMusic.artwork(for: item, size: CGSize(width: size * 2, height: size * 2)) {
                                                        Image(uiImage: img)
                                                            .resizable()
                                                            .scaledToFill()
                                                            .frame(width: size, height: size)
                                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                    } else {
                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                            .fill(Color.white.opacity(0.06))
                                                            .frame(width: size, height: size)
                                                            .overlay(
                                                                Image(systemName: "music.note")
                                                                    .foregroundStyle(.white.opacity(0.7))
                                                            )
                                                    }
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(item.title ?? "Unknown Title")
                                                            .foregroundStyle(.white)
                                                            .lineLimit(1)
                                                            .font(.footnote.weight(.semibold))
                                                        Text(item.artist ?? "Unknown Artist")
                                                            .foregroundStyle(.white.opacity(0.8))
                                                            .lineLimit(1)
                                                            .font(.caption2)
                                                    }
                                                }
                                                .frame(width: 220, alignment: .leading)
                                                .padding(10)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .fill(Color.white.opacity(0.06))
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                        case .notDetermined:
                            Button {
                                appleMusic.requestAccessAndLoad()
                            } label: {
                                Label("Allow Apple Music Access", systemImage: "music.note.list")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(minHeight: 44)
                                    .background(
                                        Capsule().fill(Color.white.opacity(0.06))
                                    )
                            }
                            .buttonStyle(.plain)

                        case .denied, .restricted:
                            if appleMusic.catalogMatches.isEmpty {
                                Button {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Label("Open Settings to Allow Apple Music", systemImage: "gearshape")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .frame(minHeight: 44)
                                        .background(
                                            Capsule().fill(Color.white.opacity(0.06))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .onAppear {
                if let id = currentAssetID {
                    Task {
                        let ref = try? await VideoAudioOverrides.shared.songReference(for: id)
                        await MainActor.run {
                            hasAssignedSong = ref != nil
                        }
                    }
                } else {
                    hasAssignedSong = false
                }
            }
            .onChange(of: currentAssetID) { _, newID in
                if let id = newID {
                    Task {
                        let ref = try? await VideoAudioOverrides.shared.songReference(for: id)
                        await MainActor.run {
                            hasAssignedSong = ref != nil
                        }
                    }
                } else {
                    hasAssignedSong = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .videoAudioOverrideChanged).compactMap { $0.userInfo?["id"] as? String }) { changedID in
                guard let currentID = currentAssetID, changedID == currentID else { return }
                Task {
                    let ref = try? await VideoAudioOverrides.shared.songReference(for: changedID)
                    await MainActor.run {
                        hasAssignedSong = ref != nil
                    }
                }
            }
        }
    }

    private struct MusicControlsQuick: View {
        let isPlaying: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Music playback")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    Button {
                        if isPlaying {
                            AppleMusicController.shared.pauseIfManaged()
                        } else {
                            AppleMusicController.shared.resumeIfManaged()
                        }
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(
                                Circle().fill(Color.white.opacity(0.08))
                            )
                            .accessibilityLabel(isPlaying ? "Pause music" : "Play music")
                    }
                    .buttonStyle(.plain)

                    Button {
                        AppleMusicController.shared.skipToPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(
                                Circle().fill(Color.white.opacity(0.06))
                            )
                            .accessibilityLabel("Previous track")
                    }
                    .buttonStyle(.plain)

                    Button {
                        AppleMusicController.shared.skipToNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(
                                Circle().fill(Color.white.opacity(0.06))
                            )
                            .accessibilityLabel("Next track")
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private struct DateGoToPanel: View {
        var onClose: () -> Void
        var onNewest: () -> Void
        var onRandom: () -> Void
        var onYearAgo: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Go to")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                                    .liquidGlass(in: Circle(), stroke: false)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                VStack(alignment: .leading, spacing: 10) {
                    RowButton(title: "Newest", systemImage: "arrow.uturn.down.circle.fill", action: onNewest)
                    RowButton(title: "Random place", systemImage: "shuffle.circle.fill", action: onRandom)
                    RowButton(title: "1 year ago", systemImage: "calendar.badge.clock", action: onYearAgo)
                }

                Spacer(minLength: 0)
            }
        }

        private struct RowButton: View {
            let title: String
            let systemImage: String
            let action: () -> Void
            var body: some View {
                Button(action: action) {
                    HStack(spacing: 10) {
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
            }
        }
    }
}