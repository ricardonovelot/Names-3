//
//  NameFacesFeedCombinedView.swift
//  Names 3
//
//  Combines Feed (TikTok-style) and Name Faces (carousel) into one seamless experience.
//  Same media in both views; hero morph animates between them as if they are one.
//

import SwiftUI
import SwiftData
import UIKit
import Photos

struct NameFacesFeedCombinedView: View {
    /// When true, parent should collapse quick input (feed has its own bottom UI).
    @Binding var isInFeedMode: Bool
    let onDismiss: () -> Void
    var initialScrollDate: Date? = nil
    var bottomBarHeight: CGFloat = 0

    enum DisplayMode {
        case feed
        case carousel
    }

    @StateObject private var coordinator = CombinedMediaCoordinator()
    @State private var displayMode: DisplayMode
    @State private var heroImage: UIImage?
    @State private var heroExpanded: Bool = true  // true = feed layout (full), false = carousel layout

    init(isInFeedMode: Binding<Bool>, onDismiss: @escaping () -> Void, initialScrollDate: Date? = nil, bottomBarHeight: CGFloat = 0) {
        self._isInFeedMode = isInFeedMode
        self.onDismiss = onDismiss
        self.initialScrollDate = initialScrollDate
        self.bottomBarHeight = bottomBarHeight
        self._displayMode = State(initialValue: initialScrollDate != nil ? .carousel : .feed)
    }

    var body: some View {
        ZStack {
            // Keep BOTH views mounted so Feed's video player never tears down during morph.
            // Only visibility changes—playback continues seamlessly.
            TikTokFeedView(coordinator: coordinator, isFeedVisible: displayMode == .feed)
                .ignoresSafeArea()
                .opacity(displayMode == .feed ? 1 : 0)
                .allowsHitTesting(displayMode == .feed)
                .zIndex(displayMode == .feed ? 1 : 0)

            NameFacesTabView(
                onDismiss: onDismiss,
                initialScrollDate: initialScrollDate,
                coordinator: coordinator,
                bottomBarHeight: max(bottomBarHeight, tabBarMinimumHeight),
                isCarouselVisible: displayMode == .carousel
            )
            .opacity(displayMode == .carousel ? 1 : 0)
            .allowsHitTesting(displayMode == .carousel)
            .zIndex(displayMode == .carousel ? 1 : 0)

            heroMorphOverlay
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: displayMode)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: heroExpanded)
        .overlay(alignment: .topTrailing) {
            modeToggleButton
        }
        .onChange(of: displayMode) { _, newMode in
            isInFeedMode = (newMode == .feed)
        }
        .onAppear {
            isInFeedMode = (displayMode == .feed)
        }
    }

    @ViewBuilder
    private var heroMorphOverlay: some View {
        if heroImage != nil, let image = heroImage {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let frame = heroExpanded
                    ? CGRect(x: 0, y: 0, width: w, height: h)
                    : CGRect(x: w * 0.1, y: h * 0.15, width: w * 0.8, height: h * 0.5)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .clipShape(RoundedRectangle(cornerRadius: heroExpanded ? 0 : 16, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
            }
            .background(Color.black.opacity(0.3))
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private func performMorphToggle() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.5)

        let assetID = coordinator.currentAssetID
        let goingToCarousel = (displayMode == .feed)

        // #region agent log
        Diagnostics.debugBridge(hypothesisId: "A", location: "NameFacesFeedCombinedView.performMorphToggle", message: "Toggle: captured assetID", data: ["assetID": assetID ?? "nil", "goingToCarousel": goingToCarousel, "scrollToAssetID_before": coordinator.scrollToAssetID ?? "nil"])
        // #endregion

        // Bridge: set target so the other view opens at same asset (consumed on appear)
        if let id = assetID {
            coordinator.setBridgeTarget(id)
        } else {
            print("[Bridge] performMorphToggle: coordinator.currentAssetID was nil – target view may open at default position")
        }

        Task { @MainActor in
            if let id = assetID {
                let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
                if let asset = asset {
                    let size = CGSize(width: 1200, height: 1200)
                    heroImage = await ImagePrefetcher.shared.requestImage(for: asset, targetSize: size)
                    heroExpanded = goingToCarousel
                } else {
                    print("[Bridge] performMorphToggle: asset \(id) not found in Photos")
                }
            }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                displayMode = goingToCarousel ? .carousel : .feed
                heroExpanded = !goingToCarousel
            }
            try? await Task.sleep(for: .milliseconds(420))
            heroImage = nil
        }
    }

    private var modeToggleButton: some View {
        Button {
            performMorphToggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: displayMode == .feed ? "person.crop.rectangle" : "play.rectangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(displayMode == .feed ? String(localized: "combined.toggle.nameFaces") : String(localized: "combined.toggle.feed"))
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .padding(.trailing, 16)
        .accessibilityLabel(displayMode == .feed
            ? String(localized: "combined.toggle.nameFaces.accessibility")
            : String(localized: "combined.toggle.feed.accessibility"))
    }
}
