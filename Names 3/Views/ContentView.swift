//
//  ContentView.swift
//  Names 3
//
//  Created by Ricardo on 14/10/24.
//
//  ContentView owns: @Query, @Environment reads, and all view-building.
//  ContentViewModel owns: mutable @State, business logic, and operations.
//

import SwiftUI
import SwiftData
import PhotosUI
import Vision
import SmoothGradient
import UIKit
import UniformTypeIdentifiers
import Photos
import TipKit
import os

// MARK: - Note Navigation Target

/// Typed navigation destination that carries both the contact and a specific note to scroll to.
struct ContactNoteNavigationTarget: Hashable {
    let contactUUID: UUID
    let noteUUID: UUID
}

// MARK: - Drag & Drop Support

struct ContactDragRecord: Codable, Transferable, Hashable {
    let uuid: UUID

    init(uuid: UUID) { self.uuid = uuid }
    init(contact: Contact) { self.uuid = contact.uuid }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .contactDragRecord)
    }
}

extension UTType {
    static let contactDragRecord = UTType(exportedAs: "com.ricardo.names3.contactdrag")
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.connectivityMonitor) private var connectivityMonitor
    @Environment(\.cloudKitMirroringResetCoordinator) private var cloudKitResetCoordinator
    @Environment(\.storageMonitor) private var storageMonitor

    /// When set, contacts are loaded off the main thread to avoid blocking during CloudKit sync.
    private let containerForAsyncLoad: ModelContainer?

    /// Live @Query for when no async-load container is provided (non-CloudKit path).
    @Query private var queryContacts: [Contact]

    /// Notes for the unified People-tab feed.
    @Query(
        filter: #Predicate<Note> { !$0.isArchived },
        sort: \Note.creationDate,
        order: .reverse
    ) private var notes: [Note]

    /// Single source of truth for all mutable UI state and operations.
    @State private var vm = ContentViewModel()

    private var contacts: [Contact] {
        containerForAsyncLoad != nil ? vm.asyncLoadedContacts : queryContacts
    }

    init(containerForAsyncLoad: ModelContainer? = nil) {
        self.containerForAsyncLoad = containerForAsyncLoad
        var descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate<Contact> { !$0.isArchived },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        _queryContacts = Query(descriptor)
    }

    private var groups: [ContactsGroup] {
        ContactsFeedView.computeGroups(contacts: contacts, parsedContacts: vm.parsedContacts)
    }

    // MARK: - Derived State from Environment

    private var isOffline: Bool { connectivityMonitor?.isOffline ?? false }
    private var usesCellular: Bool { connectivityMonitor?.usesCellular ?? false }
    private var isLowOnDeviceStorage: Bool { storageMonitor?.isLowOnDeviceStorage ?? false }
    private var isSyncResetInProgress: Bool { cloudKitResetCoordinator?.isSyncResetInProgress ?? false }

    // MARK: - Loggers

    private static let launchLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Names3",
        category: "Launch"
    )
    private static var hasLoggedBodyOnce = false

    // MARK: - Body

    var body: some View {
        let _ = {
            if !Self.hasLoggedBodyOnce {
                Self.hasLoggedBodyOnce = true
                LaunchProfiler.logCheckpoint("ContentView.body evaluated (first time)")
            }
        }()
        return NavigationStack(path: $vm.contactPath) {
            mainContentWithSheets
        }
        .safeAreaInset(edge: .bottom) { quickInputSection }
        .overlay(alignment: .bottomTrailing) {
            if vm.selectedTab == .photos {
                photosTabOverlayButtons
            }
        }
    }

    // MARK: - Content Layers

    @ViewBuilder
    private var mainContentWithLifecycle: some View {
        mainContent
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .task { await vm.loadContactsIfNeeded(container: containerForAsyncLoad, mainContext: modelContext) }
            .onAppear { vm.onMainContentAppear(groups: groups, storageMonitor: storageMonitor) }
            .onChange(of: contacts.count) { _, newCount in
                if newCount > 0 { vm.showInitialSyncState = false }
            }
            .onChange(of: groups.isEmpty) { _, isEmpty in
                if isEmpty { storageMonitor?.refreshIfNeeded() }
            }
            .task { await vm.hideSyncStateAfterDelay() }
            .onShake { vm.performMovementUndo(contacts: contacts, context: modelContext, isSyncResetInProgress: isSyncResetInProgress) }
            .onChange(of: vm.pickedImageForBatch) { _, newValue in
                if let image = newValue {
                    showBulkAddFacesWithSeed(image: image, date: Date()) {
                        vm.pickedImageForBatch = nil
                    }
                }
            }
            .onChange(of: isOffline) { _, newValue in vm.handleConnectivityChange(isOffline: newValue) }
            .onChange(of: usesCellular) { _, newValue in vm.handleCellularChange(usesCellular: newValue) }
            .onChange(of: isLowOnDeviceStorage) { _, newValue in vm.handleStorageChange(isLow: newValue) }
            .onPreferenceChange(TotalQuickInputHeightKey.self) { vm.handleQuickInputHeightChange($0) }
            .onPreferenceChange(TabBarHeightPreferenceKey.self) { vm.tabBarHeight = $0 }
            .onReceive(
                NotificationCenter.default.publisher(for: NSCloudKitMirroringDelegateWillResetSyncNotificationName)
                    .receive(on: DispatchQueue.main)
            ) { _ in vm.handleCloudKitMirroringWillResetSync() }
            .onReceive(NotificationCenter.default.publisher(for: .contactsDidChange)) { _ in
                guard let container = containerForAsyncLoad else { return }
                vm.refreshContacts(container: container, mainContext: modelContext)
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickInputRequestFocus)) { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    vm.isQuickInputExpanded = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .quizReminderTapped)) { _ in
                QuizReminderService.hasPendingQuizReminderTap = false
                vm.navigateToChoosePracticeMode()
            }
            .task { vm.handlePendingQuizReminderTap() }
            .onChange(of: vm.contactPath.isEmpty) { _, isEmpty in
                if isEmpty { vm.selectedContact = nil }
            }
            .onChange(of: vm.selectedTab) { oldTab, newTab in
                // Defer navigation path updates to next run loop to avoid "Update NavigationRequestObserver tried to update multiple times per frame"
                if oldTab == .people && newTab != .people, !vm.contactPath.isEmpty {
                    let saved = vm.contactPath
                    DispatchQueue.main.async {
                        vm.savedPeopleContactPath = saved
                        vm.contactPath = NavigationPath()
                        vm.selectedContact = nil
                    }
                } else if oldTab != .people && newTab == .people, !vm.savedPeopleContactPath.isEmpty {
                    let saved = vm.savedPeopleContactPath
                    DispatchQueue.main.async {
                        vm.contactPath = saved
                        vm.savedPeopleContactPath = NavigationPath()
                    }
                }
                switch newTab {
                case .photos:
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        vm.isQuickInputExpanded = !vm.photosIsFeedMode
                    }
                case .people:
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        vm.isQuickInputExpanded = false
                    }
                case .journal:
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        vm.isQuickInputExpanded = false
                    }
                case .practice:
                    break
                case .albums:
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        vm.isQuickInputExpanded = false
                    }
                }
            }
            .onChange(of: vm.photosIsFeedMode) { _, inFeedMode in
                guard vm.selectedTab == .photos else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                    vm.isQuickInputExpanded = !inFeedMode
                }
            }
            .safeAreaInset(edge: .top) { topBannersView }
    }

    @ViewBuilder
    private var mainContentWithSheets: some View {
        mainContentWithLifecycle
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay { loadingOverlay }
            .toolbarBackground(.hidden)
            .navigationTitle(tabToolbarTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { tabToolbarContent }
            .modifier(MainContentSheetsModifier(
                vm: vm,
                modelContext: modelContext,
                contacts: contacts,
                groupDateEditSheetContent: { AnyView(groupDateEditSheetContent($0)) }
            ))
    }

    // MARK: - Tab Container

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            NavigationStack {
                Group {
                    unifiedPeopleContent
                }
                .ignoresSafeArea(.container, edges: .top)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .opacity(vm.selectedTab == .people ? 1 : 0)
            .allowsHitTesting(vm.selectedTab == .people)

            NameFacesFeedCombinedView(
                isInFeedMode: $vm.photosIsFeedMode,
                onDismiss: {
                    vm.faceNamingInitialDate = nil
                    vm.selectedTab = .people
                },
                initialScrollDate: vm.faceNamingInitialDate,
                bottomBarHeight: vm.tabBarHeight,
                isTabActive: vm.selectedTab == .photos,
                viewModel: vm
            )
            .opacity(vm.selectedTab == .photos ? 1 : 0)
            .allowsHitTesting(vm.selectedTab == .photos)

            JournalTabView(bottomBarHeight: vm.tabBarHeight)
                .opacity(vm.selectedTab == .journal ? 1 : 0)
                .allowsHitTesting(vm.selectedTab == .journal)

            AlbumsTabView(bottomBarHeight: vm.tabBarHeight)
                .opacity(vm.selectedTab == .albums ? 1 : 0)
                .allowsHitTesting(vm.selectedTab == .albums)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: vm.selectedTab)
    }

    // MARK: - Photos Tab Overlay Buttons

    private var photosTabOverlayButtons: some View {
        let size: CGFloat = 64
        let bottomPadding = max(vm.tabBarHeight, tabBarMinimumHeight) + 16
        return VStack(spacing: 12) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred(intensity: 0.6)
                vm.photosSaveOrRemoveHandler?()
            } label: {
                Image(systemName: vm.photosCurrentItemSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: size, height: size)
                    .liquidGlass(in: Circle(), stroke: true, style: .translucent)
                    .contentShape(Circle())
            }
            .buttonStyle(TabBarButtonStyle())
            .accessibilityLabel(vm.photosCurrentItemSaved ? "Remove from Profile" : "Save to Profile")

            let isFeed = vm.photosIsFeedMode
            let icon = isFeed ? "person.2.fill" : "play.rectangle.fill"
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred(intensity: 0.6)
                vm.photosIsFeedMode.toggle()
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: size, height: size)
                    .liquidGlass(in: Circle(), stroke: true, style: .translucent)
                    .contentShape(Circle())
            }
            .buttonStyle(TabBarButtonStyle())
            .accessibilityLabel(isFeed ? "Switch to Name Faces" : "Switch to Feed")
        }
        .padding(.trailing, 16)
        .padding(.bottom, bottomPadding)
    }

    // MARK: - Unified People Content

    @ViewBuilder
    private var unifiedPeopleContent: some View {
        unifiedFeedView
            .opacity(vm.showInlinePhotoPicker || vm.showFullPhotoGrid ? 0 : 1)
            .offset(y: vm.showInlinePhotoPicker || vm.showFullPhotoGrid ? -16 : 0)
            .allowsHitTesting(!vm.showInlinePhotoPicker && !vm.showFullPhotoGrid)
            .zIndex(0)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: vm.showInlinePhotoPicker)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: vm.showFullPhotoGrid)

        if vm.allowPhotoDependentViews {
            inlinePhotoPickerContent
            if let payload = vm.fullPhotoGridPayload {
                fullPhotoGridInlineView(payload: payload)
            }
        }
    }

    @ViewBuilder
    private var inlinePhotoPickerContent: some View {
        if vm.showInlinePhotoPicker {
            PhotosInlineView(contactsContext: modelContext, isVisible: true) { image, _ in
                vm.pickedImageForBatch = image
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    vm.showInlinePhotoPicker = false
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(vm.showFullPhotoGrid ? 0 : 1)
        }
    }

    @ViewBuilder
    private var unifiedFeedView: some View {
        UnifiedPeopleFeedView(
            contacts: contacts,
            parsedContacts: vm.parsedContacts,
            notes: notes,
            filter: vm.peopleFeedFilter,
            feedRefreshTrigger: vm.feedRefreshTrigger,
            useSafeTitle: isSyncResetInProgress,
            showInitialSyncState: vm.showInitialSyncState,
            isLowOnDeviceStorage: isLowOnDeviceStorage,
            isOffline: isOffline,
            onContactSelected: { uuid in
                vm.contactNavigatedFromQuickInput = false
                vm.contactPath.append(uuid)
            },
            onNoteSelected: { contactUUID, noteUUID in
                vm.contactPath.append(
                    ContactNoteNavigationTarget(contactUUID: contactUUID, noteUUID: noteUUID)
                )
            },
            onImport: { group in
                guard !group.isLongAgo else { return }
                if isOffline {
                    vm.showOfflineActionAlert = true
                    return
                }
                vm.openFullPhotoGrid(scope: .all, initialScrollDate: group.date)
            },
            onEditDate: { group in
                guard !group.isLongAgo else { return }
                vm.groupForDateEdit = group.asContactsGroup
            },
            onEditTag: { group in
                guard !group.isLongAgo else { return }
                vm.groupForTagEdit = group.asContactsGroup
            },
            onRenameTag: { _ in
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    vm.showManageTags = true
                }
            },
            onDeleteAll: { group in
                guard !group.isLongAgo else { return }
                vm.deleteAllEntries(in: group.asContactsGroup, context: modelContext)
            },
            onChangeDateForContact: { contact in vm.contactForDateEdit = contact },
            onTapHeader: { group in
                guard !group.isLongAgo else { return }
                vm.faceNamingInitialDate = group.date
                vm.photosIsFeedMode = false
                vm.selectedTab = .photos
            },
            onDropRecords: { records, group in
                vm.handleDrop(
                    records,
                    to: group.asContactsGroup,
                    contacts: contacts,
                    context: modelContext,
                    isSyncResetInProgress: isSyncResetInProgress
                )
            }
        )
    }

    // MARK: - Banners

    @ViewBuilder
    private var topBannersView: some View {
        VStack(spacing: 8) {
            OfflineBannerView(
                isOffline: isOffline,
                isDismissed: vm.offlineBannerDismissed,
                onDismiss: { vm.offlineBannerDismissed = true }
            )
            CellularDataBannerView(
                usesCellular: usesCellular,
                isViewingFeed: vm.selectedTab == .photos && vm.photosIsFeedMode,
                isDismissed: vm.cellularBannerDismissed,
                onDismiss: { vm.cellularBannerDismissed = true },
                onTapToSettings: { vm.showSettings = true }
            )
            LowStorageBannerView(
                isLowStorage: isLowOnDeviceStorage,
                isDismissed: vm.storageBannerDismissed,
                onDismiss: { vm.storageBannerDismissed = true }
            )
        }
    }

    // MARK: - Quick Input

    @ViewBuilder
    private var quickInputSection: some View {
        let isJournalTab = vm.selectedTab == .journal
        QuickInputBottomBar(
            selectedTab: $vm.selectedTab,
            isQuickInputExpanded: $vm.isQuickInputExpanded,
            canShowQuickInput: !vm.showQuizView && !(vm.selectedTab == .photos && vm.photosIsFeedMode),
            showMusicButtonInsteadOfQuickInput: (vm.selectedTab == .photos && vm.photosIsFeedMode) || (vm.selectedTab == .albums),
            onMusicTapped: {
                vm.photosMusicPickerPayload = ContentViewModel.MusicPickerPayload(
                    assetIDs: vm.selectedTab == .photos ? vm.photosCurrentItemAssetIDs : []
                )
            },
            musicButtonDisabled: vm.selectedTab == .photos && vm.photosCurrentItemAssetIDs.isEmpty,
            onSameTabTapped: { tab in
                switch tab {
                case .people:
                    if !vm.contactPath.isEmpty {
                        DispatchQueue.main.async {
                            vm.contactPath = NavigationPath()
                            vm.selectedContact = nil
                        }
                    } else {
                        NotificationCenter.default.post(name: .peopleFeedScrollToTop, object: nil)
                    }
                case .journal: NotificationCenter.default.post(name: .journalFeedScrollToTop, object: nil)
                case .practice: break
                case .photos: break  // No scroll-to-top when re-tapping Photos tab
                case .albums: break
                }
            }
        ) {
            if isJournalTab {
                JournalQuickInputView(inlineInBar: true)
                    .id("journal-quick-input")
            } else {
                QuickInputView(
                    parsedContacts: $vm.parsedContacts,
                    selectedContact: $vm.selectedContact,
                    onQuizTap: { vm.showPracticeSheet = true }, onPhotosTap: {
                        vm.faceNamingInitialDate = nil
                        vm.selectedTab = .photos
                    }, showQuizButton: true, showPhotosButton: vm.selectedTab != .photos, onContactSelectedForNavigation: { contact in
                        vm.contactNavigatedFromQuickInput = true
                        vm.contactPath.append(contact.uuid)
                    },
                    onBackspaceWhenEmptyToGoBack: {
                        NotificationCenter.default.post(name: .quickInputLockFocus, object: nil)
                        if !vm.contactPath.isEmpty { vm.contactPath.removeLast() }
                        vm.selectedContact = nil
                    },
                    onContactCreatedForNavigation: { contact in
                        vm.contactNavigatedFromQuickInput = true
                        vm.contactPath.append(contact.uuid)
                    },
                    faceDetectionViewModel: vm.fullPhotoGridFaceViewModel,
                    onFaceSelected: { vm.handleFaceSelectedFromCarousel(index: $0) },
                    onPhotoPicked: { image, _ in vm.pickedImageForBatch = image },
                    inlineInBar: true,
                    cameraInSeparateBubble: true,
                    faceNamingMode: vm.selectedTab == .photos
                )
                .id(vm.quickInputResetID)
            }
        }
    }

    // MARK: - Photos Grid (Full Inline)

    @ViewBuilder
    private func fullPhotoGridInlineView(payload: ContentViewModel.PhotosSheetPayload) -> some View {
        PhotosFullGridInlineView(
            scope: payload.scope,
            contactsContext: modelContext,
            initialScrollDate: payload.initialScrollDate,
            faceDetectionViewModel: $vm.fullPhotoGridFaceViewModel,
            onPhotoPicked: { image, _ in
                vm.pickedImageForBatch = image
                vm.closeFullPhotoGrid()
            },
            onDismiss: { vm.closeFullPhotoGrid() },
            attemptQuickAssign: { [modelContext] image, _ in
                await vm.attemptQuickAssign(image: image, context: modelContext)
            }
        )
        .opacity(vm.showFullPhotoGrid ? 1 : 0)
        .offset(y: vm.showFullPhotoGrid ? 0 : 32)
        .allowsHitTesting(vm.showFullPhotoGrid)
        .zIndex(2)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: vm.showFullPhotoGrid)
    }

    // MARK: - Loading Overlay

    @ViewBuilder
    private var loadingOverlay: some View {
        if vm.isLoading {
            LoadingOverlay(message: "Loading…")
        }
    }

    // MARK: - Tab Toolbar (single root toolbar, tab-specific content)

    private var tabToolbarTitle: String {
        switch vm.selectedTab {
        case .people, .photos: return ""
        case .journal: return "Recalled Gratitude"
        case .practice: return ""
        case .albums: return ""
        }
    }

    @ToolbarContentBuilder
    private var tabToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            switch vm.selectedTab {
            case .people where !vm.showQuizView && vm.selectedContact == nil && vm.contactPath.isEmpty:
                Button {
                    vm.peopleFeedFilter = vm.peopleFeedFilter == .people ? .peopleWithNotes : .people
                } label: {
                    Image(systemName: vm.peopleFeedFilter.systemImage)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Filter: \(vm.peopleFeedFilter.title)")
                .accessibilityHint("Tap to cycle filter mode")

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
                    Button(action: { vm.showPracticeSheet = true }) {
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
                        Button(action: presentLimitedLibraryPicker) {
                            Label("Manage Photos Selection", systemImage: "plus.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .frame(width: 44, height: 44)
                .fontWeight(.semibold)

            case .journal:
                Button {
                    vm.showJournalNewEntrySheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .fontWeight(.semibold)
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Write new gratitude entry")

            case .photos:
                Menu {
                    Button { vm.showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
                        Divider()
                        Button(action: presentLimitedLibraryPicker) {
                            Label("Manage Photos Selection", systemImage: "plus.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .fontWeight(.semibold)
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Options")

            default:
                Color.clear.frame(width: 44, height: 44)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Group Date Edit Sheet

    @ViewBuilder
    private func groupDateEditSheetContent(_ group: ContactsGroup) -> some View {
        let primary = group.contacts.first ?? group.parsedContacts.first
        let others = (group.contacts + group.parsedContacts).filter { primary != nil && $0.id != primary!.id }
        if let primary {
            CustomDatePicker(
                contact: primary,
                additionalContactsToApply: others.isEmpty ? nil : others,
                onRecordUndo: vm.pushMovementUndoEntry
            )
        }
    }
}

// MARK: - UIKit Interop

private extension ContentView {
    func showBulkAddFacesWithSeed(image: UIImage, date: Date, completion: (() -> Void)? = nil) {
        let root = UIHostingController(
            rootView: BulkAddFacesView(contactsContext: modelContext, initialImage: image, initialDate: date)
                .modelContainer(BatchModelContainer.shared)
        )
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else {
            completion?()
            return
        }
        root.modalPresentationStyle = .formSheet
        rootVC.present(root, animated: true) { completion?() }
    }

    func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootVC)
    }
}

// MARK: - Main Content Sheets Modifier

/// Extracted to avoid "unable to type-check this expression in reasonable time".
private struct MainContentSheetsModifier: ViewModifier {
    @Bindable var vm: ContentViewModel
    let modelContext: ModelContext
    let contacts: [Contact]
    let groupDateEditSheetContent: (ContactsGroup) -> AnyView

    func body(content: Content) -> some View {
        content
            .offlineActionAlert(showOfflineAlert: $vm.showOfflineActionAlert)
            .photosPicker(isPresented: $vm.showPhotosPicker, selection: $vm.selectedItem, matching: .images)
            .sheet(isPresented: $vm.showDeletedView) { DeletedView() }
            .sheet(item: $vm.photosMusicPickerPayload) { payload in
                AppleMusicSearchScreen(assetIDs: payload.assetIDs) {
                    vm.photosMusicPickerPayload = nil
                }
            }
            .sheet(isPresented: $vm.showBulkAddFaces) {
                BulkAddFacesView(contactsContext: modelContext)
                    .modelContainer(BatchModelContainer.shared)
            }
            .sheet(item: $vm.contactForDateEdit) { contact in
                CustomDatePicker(contact: contact, onRecordUndo: vm.pushMovementUndoEntry)
            }
            .sheet(item: $vm.groupForDateEdit, onDismiss: { vm.groupForDateEdit = nil }) { group in
                groupDateEditSheetContent(group)
            }
            .sheet(item: $vm.groupForTagEdit, onDismiss: { vm.groupForTagEdit = nil }) { group in
                let initialTag = (group.contacts + group.parsedContacts).compactMap { ($0.tags ?? []).first }.first
                TagPickerView(mode: .groupApply(initialTag: initialTag) { vm.applyGroupTagChange($0, context: modelContext) })
            }
            .sheet(isPresented: $vm.showManageTags) { TagPickerView(mode: .manage) }
            .sheet(isPresented: $vm.showSettings) { SettingsView() }
            .sheet(isPresented: $vm.showQuickNotesFeed) { QuickNotesFeedView() }
            .sheet(isPresented: $vm.showJournalNewEntrySheet) { JournalEntryFormView() }
            .sheet(isPresented: $vm.showPracticeSheet, onDismiss: {
                vm.showQuizView = false
                vm.selectedQuizType = nil
            }) {
                PracticeTabView(
                    contacts: contacts,
                    showQuizView: vm.showQuizView,
                    selectedQuizType: vm.selectedQuizType,
                    quizResetTrigger: vm.quizResetTrigger,
                    onSelectQuiz: {
                        vm.selectedQuizType = $0
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            vm.showQuizView = true
                        }
                    },
                    onQuizComplete: {
                        QuizReminderService.shared.maybeRequestPermissionOnQuizExit()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            vm.showQuizView = false
                        }
                        vm.quizResetTrigger = UUID()
                        vm.selectedQuizType = nil
                        vm.showPracticeSheet = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { vm.showPracticeSheet = false }
                    }
                }
            }
            .alert("Exit Quiz?", isPresented: $vm.showExitQuizConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Exit", role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        vm.showQuizView = false
                    }
                }
            } message: {
                Text("You can resume this quiz later from where you left off.")
            }
            .navigationDestination(for: UUID.self) { uuid in
                if let contact = contacts.first(where: { $0.uuid == uuid }) {
                    ContactDetailsView(
                        contact: contact,
                        onBack: {
                            NotificationCenter.default.post(name: .quickInputLockFocus, object: nil)
                            if !vm.contactPath.isEmpty { vm.contactPath.removeLast() }
                            vm.selectedContact = nil
                        },
                        onAppearSyncQuickInput: {
                            vm.selectedContact = contact
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                vm.isQuickInputExpanded = true
                            }
                            if vm.contactNavigatedFromQuickInput {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(200))
                                    NotificationCenter.default.post(name: .quickInputRequestFocus, object: nil)
                                }
                            }
                        },
                        onRequestAddNote: {
                            vm.selectedContact = contact
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                vm.isQuickInputExpanded = true
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(200))
                                NotificationCenter.default.post(name: .quickInputRequestFocus, object: nil)
                            }
                        }
                    )
                }
            }
            .navigationDestination(for: ContactNoteNavigationTarget.self) { target in
                if let contact = contacts.first(where: { $0.uuid == target.contactUUID }) {
                    ContactDetailsView(
                        contact: contact,
                        onBack: {
                            NotificationCenter.default.post(name: .quickInputLockFocus, object: nil)
                            if !vm.contactPath.isEmpty { vm.contactPath.removeLast() }
                            vm.selectedContact = nil
                        },
                        onAppearSyncQuickInput: {
                            vm.selectedContact = contact
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                vm.isQuickInputExpanded = true
                            }
                            if vm.contactNavigatedFromQuickInput {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(200))
                                    NotificationCenter.default.post(name: .quickInputRequestFocus, object: nil)
                                }
                            }
                        },
                        onRequestAddNote: {
                            vm.selectedContact = contact
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                vm.isQuickInputExpanded = true
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(200))
                                NotificationCenter.default.post(name: .quickInputRequestFocus, object: nil)
                            }
                        },
                        highlightedNoteUUID: target.noteUUID
                    )
                }
            }
    }
}

// MARK: - Preference Keys

private struct BottomInsetHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Previews

#Preview("List") {
    ContentView().modelContainer(for: [Contact.self, Note.self, Tag.self], inMemory: true)
}

#Preview("Contact Detail") {
    ModelContainerPreview(ModelContainer.sample) {
        NavigationStack {
            ContactDetailsView(contact: .ross)
        }
    }
}
