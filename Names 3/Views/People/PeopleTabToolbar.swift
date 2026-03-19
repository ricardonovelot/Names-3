//
//  PeopleTabToolbar.swift
//  Names 3
//
//  Toolbar content for the People tab.
//  Trailing items: filter button (1-tap cycle: People ↔ People with notes) and 3-dot menu.
//

import SwiftUI
import SwiftData
import Photos

// MARK: - PeopleTabToolbar

struct PeopleTabToolbar: ToolbarContent {
    @Bindable var vm: ContentViewModel
    let contacts: [Contact]
    let modelContext: ModelContext
    let isSyncResetInProgress: Bool
    let onPresentLimitedLibraryPicker: () -> Void
    var onOpenPractice: () -> Void = {}

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if vm.selectedTab == .people, !vm.showQuizView, vm.selectedContact == nil, vm.contactPath.isEmpty {

            // MARK: Filter button (1 tap cycles: People ↔ People with notes), left of 3-dot
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vm.peopleFeedFilter = vm.peopleFeedFilter == .people ? .peopleWithNotes : .people
                } label: {
                    Image(systemName: vm.peopleFeedFilter.systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Filter: \(vm.peopleFeedFilter.title)")
                .accessibilityHint("Tap to cycle filter mode")
            }

            // MARK: Options menu (3-dot)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if !vm.movementUndoStack.isEmpty {
                        Button {
                            vm.performMovementUndo(
                                contacts: contacts,
                                context: modelContext,
                                isSyncResetInProgress: isSyncResetInProgress
                            )
                        } label: {
                            Label(String(localized: "contacts.undo.move"), systemImage: "arrow.uturn.backward")
                        }
                        Divider()
                    }

                    Button { vm.showQuickNotesFeed = true } label: {
                        Label("Quick Notes", systemImage: "note.text")
                    }

                    Button(action: onOpenPractice) {
                        Label(String(localized: "tab.practice"), systemImage: "rectangle.stack.fill")
                    }

                    Divider()

                    Button { vm.showDeletedView = true } label: {
                        Label("Deleted", systemImage: "trash")
                    }

                    Divider()

                    Button { vm.showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }

                    if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
                        Button(action: onPresentLimitedLibraryPicker) {
                            Label("Manage Photos Selection", systemImage: "plus.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .fontWeight(.semibold)
            }
        }
    }
}
