//
//  NameFacesFeedCombinedView.swift
//  Names 3
//
//  SwiftUI wrapper for NameFacesFeedCombinedViewController.
//  Combines Feed (TikTok-style) and Name Faces (carousel) into one UIKit-hosted experience.
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
    /// When false, video is paused (tab not selected). Matches TikTok/Instagram behavior.
    var isTabActive: Bool = true
    /// For Save button state and handler registration.
    var viewModel: ContentViewModel?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NameFacesFeedCombinedRepresentable(
            isInFeedMode: $isInFeedMode,
            onDismiss: onDismiss,
            initialScrollDate: initialScrollDate,
            bottomBarHeight: max(bottomBarHeight, tabBarMinimumHeight),
            isTabActive: isTabActive,
            modelContext: modelContext,
            viewModel: viewModel
        )
        .ignoresSafeArea()
    }
}

// MARK: - UIViewControllerRepresentable

private struct NameFacesFeedCombinedRepresentable: UIViewControllerRepresentable {
    @Binding var isInFeedMode: Bool
    let onDismiss: () -> Void
    let initialScrollDate: Date?
    let bottomBarHeight: CGFloat
    var isTabActive: Bool
    let modelContext: ModelContext
    var viewModel: ContentViewModel?

    func makeUIViewController(context: Context) -> NameFacesFeedCombinedViewController {
        let vc = NameFacesFeedCombinedViewController(
            modelContext: modelContext,
            onDismiss: onDismiss,
            initialScrollDate: initialScrollDate,
            bottomBarHeight: bottomBarHeight,
            initialDisplayMode: (initialScrollDate != nil ? .carousel : nil) ?? (isInFeedMode ? .feed : .carousel),
            viewModel: viewModel
        )
        vc.setOnDisplayModeChange { inFeedMode in
            DispatchQueue.main.async { isInFeedMode = inFeedMode }
        }
        return vc
    }

    func updateUIViewController(_ vc: NameFacesFeedCombinedViewController, context: Context) {
        vc.setBottomBarHeight(bottomBarHeight)
        vc.setTabActive(isTabActive)
        // Defer to next run loop to avoid "Modifying state during view update" when called from SwiftUI update cycle
        DispatchQueue.main.async { vc.applyRequestedMode(inFeedMode: isInFeedMode) }
    }
}
