//
//  NameFacesTabView.swift
//  Names 3
//
//  Inline Name Faces tab: carousel face naming integrated into the tab.
//

import SwiftUI
import SwiftData
import Photos

struct NameFacesTabView: View {
    let onDismiss: () -> Void
    var initialScrollDate: Date? = nil
    /// When non-nil (e.g. when switching from Feed), scroll to this asset.
    var initialAssetID: String? = nil
    var coordinator: CombinedMediaCoordinator? = nil
    /// Height of the tab bar / QuickInput overlay so content doesn't sit under it.
    var bottomBarHeight: CGFloat = 0
    /// When true, carousel is the visible mode (Feed→Carousel bridge consumes here).
    var isCarouselVisible: Bool = true

    var body: some View {
        WelcomeFaceNamingView(
            onDismiss: onDismiss,
            initialScrollDate: initialScrollDate,
            initialAssetID: initialAssetID,
            useQuickInputForName: true,
            coordinator: coordinator,
            isCarouselVisible: isCarouselVisible
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: bottomBarHeight)
        }
    }
}
