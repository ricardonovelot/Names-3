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

    var body: some View {
        WelcomeFaceNamingView(
            onDismiss: onDismiss,
            initialScrollDate: initialScrollDate,
            useQuickInputForName: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
