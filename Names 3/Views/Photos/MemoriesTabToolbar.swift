//
//  MemoriesTabToolbar.swift
//  Names 3
//
//  Toolbar for the Memories (Photos) tab. Triple-dot menu for settings.
//

import SwiftUI
import Photos

struct MemoriesTabToolbar: ToolbarContent {
    var onOpenSettings: () -> Void = {}
    var onPresentLimitedLibraryPicker: (() -> Void)? = nil

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { onOpenSettings() } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                if let onPresent = onPresentLimitedLibraryPicker,
                   PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
                    Divider()
                    Button(action: onPresent) {
                        Label("Manage Photos Selection", systemImage: "plus.circle")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .fontWeight(.semibold)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Options")
        }
    }
}
