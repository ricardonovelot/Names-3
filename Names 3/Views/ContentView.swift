//
//  ContentView.swift
//  Names 3
//
//  Created by Ricardo on 14/10/24.
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

// MARK: - Drag & Drop Support

struct ContactDragRecord: Codable, Transferable, Hashable {
    let uuid: UUID

    init(uuid: UUID) {
        self.uuid = uuid
    }

    init(contact: Contact) {
        self.uuid = contact.uuid
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .contactDragRecord)
    }
}

extension UTType {
    static let contactDragRecord = UTType(exportedAs: "com.ricardo.names3.contactdrag")
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.connectivityMonitor) private var connectivityMonitor
    @Environment(\.cloudKitMirroringResetCoordinator) private var cloudKitResetCoordinator
    @Environment(\.storageMonitor) private var storageMonitor

    /// When set, loads contacts on background thread to avoid blocking main during CloudKit sync.
    private let containerForAsyncLoad: ModelContainer?
    @Query private var queryContacts: [Contact]
    @State private var asyncLoadedContacts: [Contact] = []
    @State private var asyncLoadComplete = false

    private var contacts: [Contact] {
        containerForAsyncLoad != nil ? asyncLoadedContacts : queryContacts
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
    @State private var parsedContacts: [Contact] = []
    @State private var selectedContact: Contact?
    /// Path-based navigation for contact detail (avoids duplicate toolbars from NavigationLink).
    @State private var contactPathIds: [UUID] = []
    
    @State private var selectedItem: PhotosPickerItem?
    
    @State private var isAtBottom = true
    private let dragThreshold: CGFloat = 100
    
    @State private var date = Date()

    @State private var showPhotosPicker = false
    @State private var showQuizView = false
    @State private var selectedQuizType: QuizType?
    @State private var selectedTab: MainTab = .people
    @State private var isQuickInputExpanded = true  // expanded by default on People tab
    @State private var showBulkAddFaces = false

    @State private var name = ""
    @State private var hashtag = ""
    
    @State private var groupForDateEdit: contactsGroup?
    @State private var isLoading = false
    @State private var showGroupTagPicker = false
    @State private var groupForTagEdit: contactsGroup?
    @State private var showManageTags = false
    @State private var selectedTag: Tag?
    @State private var newTagName: String = ""
    @State private var showDeletedView = false
    @State private var showInlineQuickNotes = false
    @State private var showInlinePhotoPicker = false
    @State private var hasPendingQuickNoteInput = false
    @State private var quickInputResetID = 0
    @State private var showAllGroupTagDates = false
    @State private var contactForDateEdit: Contact?
    @State private var bottomInputHeight: CGFloat = 0
    @State private var tabBarHeight: CGFloat = 0
    @State private var fullPhotoGridFaceViewModel: FaceDetectionViewModel? = nil
    @State private var showSettings = false
    @State private var showQuickNotesFeed = false
    @State private var showExitQuizConfirmation = false
    @State private var quizResetTrigger = UUID()
    /// When set, Name Faces tab scrolls to this date (e.g. from group header tap); nil when opened from camera button.
    @State private var faceNamingInitialDate: Date?
    /// Show "Syncing…" empty state for a short window after launch when feed is empty (likely initial CloudKit sync).
    @State private var showInitialSyncState = true
    @State private var offlineBannerDismissed = false
    @State private var showOfflineActionAlert = false
    /// When Name Faces tab is in feed mode (vs carousel), collapse quick input.
    @State private var nameFacesIsFeedMode = true
    /// Undo stack for contact moves (drag-to-group and date picker). Each entry is one user action and can affect multiple contacts.
    @State private var movementUndoStack: [[ContactMovementSnapshot]] = []
    private let maxMovementUndoStackSize = 50
    
    private struct PhotosSheetPayload: Identifiable, Hashable {
        let id = UUID()
        let scope: PhotosPickerScope
        let initialScrollDate: Date?
        
        init(scope: PhotosPickerScope, initialScrollDate: Date? = nil) {
            self.scope = scope
            self.initialScrollDate = initialScrollDate
        }
    }
    @State private var pickedImageForBatch: UIImage?
    
    @State private var showFullPhotoGrid = false
    @State private var fullPhotoGridPayload: PhotosSheetPayload?
    /// Deferred so first frame shows contacts list only; photo views (ImageCacheService, etc.) load after.
    @State private var allowPhotoDependentViews = false

    var groups: [contactsGroup] {
        let calendar = Calendar.current
        
        let longAgoContacts = contacts.filter { $0.isMetLongAgo }
        let regularContacts = contacts.filter { !$0.isMetLongAgo }
        
        let longAgoParsed = parsedContacts.filter { $0.isMetLongAgo }
        let regularParsed = parsedContacts.filter { !$0.isMetLongAgo }
        
        let groupedRegularContacts = Dictionary(grouping: regularContacts) { contact in
            calendar.startOfDay(for: contact.timestamp)
        }
        let groupedRegularParsed = Dictionary(grouping: regularParsed) { parsedContact in
            calendar.startOfDay(for: parsedContact.timestamp)
        }
        
        let allDates = Set(groupedRegularContacts.keys).union(groupedRegularParsed.keys)
        
        var result: [contactsGroup] = []
        
        if !longAgoContacts.isEmpty || !longAgoParsed.isEmpty {
            let longAgoGroup = contactsGroup(
                date: .distantPast,
                contacts: longAgoContacts.sorted { $0.timestamp < $1.timestamp },
                parsedContacts: longAgoParsed.sorted { $0.timestamp < $1.timestamp },
                isLongAgo: true
            )
            result.append(longAgoGroup)
        }
        
        let datedGroups = allDates.map { date in
            let sortedContacts = (groupedRegularContacts[date] ?? []).sorted { $0.timestamp < $1.timestamp }
            let sortedParsedContacts = (groupedRegularParsed[date] ?? []).sorted { $0.timestamp < $1.timestamp }
            return contactsGroup(
                date: date,
                contacts: sortedContacts,
                parsedContacts: sortedParsedContacts,
                isLongAgo: false
            )
        }
        .sorted { $0.date < $1.date }
        
        result.append(contentsOf: datedGroups)
        return result
    }
    
    private let gridSpacing: CGFloat = 10.0
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10.0),
        GridItem(.flexible(), spacing: 10.0),
        GridItem(.flexible(), spacing: 10.0),
        GridItem(.flexible(), spacing: 10.0)
    ]

    /// Shown when there are no contact groups (e.g. no data yet, or after CloudKit sync reset).
    /// Shows "Syncing…" when mirroring is reset or initial sync; "Not syncing — storage full" when device is out of space.
    @ViewBuilder
    private var feedEmptyState: some View {
        let showSyncing = cloudKitResetCoordinator?.isSyncResetInProgress == true
            || (groups.isEmpty && showInitialSyncState && !isOffline)
        let showNoStorage = groups.isEmpty && (storageMonitor?.isLowOnDeviceStorage == true) && !showSyncing
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            if showSyncing {
                ProgressView()
                    .scaleEffect(1.2)
                Text(String(localized: "feed.empty.syncing"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if showNoStorage {
                Image(systemName: "externaldrive.fill.badge.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(String(localized: "feed.empty.no_storage.title"))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                Text(String(localized: "feed.empty.no_storage.message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(String(localized: "feed.empty.title"))
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(String(localized: "feed.empty.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Text(String(localized: "feed.empty.icloud.hint"))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 4)
            }
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    @ViewBuilder
    private var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if groups.isEmpty {
                        feedEmptyState
                    }
                    ForEach(groups) { group in
                        GroupSectionView(
                            group: group,
                            isLast: group.id == groups.last?.id,
                            useSafeTitle: cloudKitResetCoordinator?.isSyncResetInProgress ?? false,
                            onImport: {
                                guard !group.isLongAgo else { return }
                                if isOffline {
                                    showOfflineActionAlert = true
                                    return
                                }
                                openFullPhotoGrid(scope: .all, initialScrollDate: group.date)
                            },
                            onEditDate: {
                                guard !group.isLongAgo else { return }
                                groupForDateEdit = group
                            },
                            onEditTag: {
                                guard !group.isLongAgo else { return }
                                groupForTagEdit = group
                                Task {
                                    try? await Task.sleep(for: .milliseconds(150))
                                    showGroupTagPicker = true
                                }
                            },
                            onRenameTag: {
                                guard !group.isLongAgo else { return }
                                Task {
                                    try? await Task.sleep(for: .milliseconds(150))
                                    showManageTags = true
                                }
                            },
                            onDeleteAll: {
                                guard !group.isLongAgo else { return }
                                deleteAllEntries(in: group)
                            },
                            onChangeDateForContact: { contact in
                                contactForDateEdit = contact
                            },
                            onTapHeader: {
                                guard !group.isLongAgo else { return }
                                faceNamingInitialDate = group.date
                                nameFacesIsFeedMode = false  // open carousel for face naming
                                selectedTab = .nameFaces
                            },
                            onDropRecords: { records in
                                handleDrop(records, to: group)
                            }
                        )
                    }
                }
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .background(Color(UIColor.systemGroupedBackground))
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    if let id = bottomMostID() {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Main Body
    
    private var isOffline: Bool {
        connectivityMonitor?.isOffline ?? false
    }

    private static let launchLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "Launch")
    private static var hasLoggedBodyOnce = false

    var body: some View {
        let _ = {
            if !Self.hasLoggedBodyOnce {
                Self.hasLoggedBodyOnce = true
                LaunchProfiler.logCheckpoint("ContentView.body evaluated (first time)")
            }
        }()
        return NavigationStack(path: $contactPathIds) {
            mainContent
                .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
                .task {
                    if let container = containerForAsyncLoad {
                        asyncLoadedContacts = await FeedContactsLoader.loadContacts(
                            container: container,
                            mainContext: modelContext,
                            fetchLimit: 500
                        )
                        asyncLoadComplete = true
                    } else {
                        asyncLoadComplete = true
                    }
                }
                .onAppear {
                    LaunchProfiler.logCheckpoint("ContentView mainContent appeared")
                    Self.launchLogger.info("🚀 [Launch] Feed state: contacts=\(self.contacts.count) parsed=\(self.parsedContacts.count) groups=\(self.groups.count)")
                    if groups.isEmpty { storageMonitor?.refreshIfNeeded() }
                    // Defer photo-dependent views so contacts feed paints first; they init ImageCacheService etc.
                    DispatchQueue.main.async {
                        allowPhotoDependentViews = true
                    }
                }
                .onChange(of: contacts.count) { _, newCount in
                    if newCount > 0 { showInitialSyncState = false }
                }
                .onChange(of: groups.isEmpty) { _, isEmpty in
                    if isEmpty { storageMonitor?.refreshIfNeeded() }
                }
                .task {
                    // Stop showing "Syncing…" after a reasonable initial-sync window (e.g. 2 min)
                    try? await Task.sleep(for: .seconds(120))
                    showInitialSyncState = false
                }
                .onShake {
                    performMovementUndo()
                }
                .onChange(of: pickedImageForBatch) { oldValue, newValue in
                    handlePickedImageChange(newValue)
                }
                .onChange(of: isOffline) { _, newValue in
                    if newValue == false {
                        offlineBannerDismissed = false
                    }
                }
                .onPreferenceChange(TotalQuickInputHeightKey.self) { height in
                    handleQuickInputHeightChange(height)
                }
                .onPreferenceChange(TabBarHeightPreferenceKey.self) { height in
                    tabBarHeight = height
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: NSCloudKitMirroringDelegateWillResetSyncNotificationName)
                        .receive(on: DispatchQueue.main)
                ) { _ in
                    handleCloudKitMirroringWillResetSync()
                }
                .onReceive(NotificationCenter.default.publisher(for: .quickInputRequestFocus)) { _ in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        isQuickInputExpanded = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .quizReminderTapped)) { _ in
                    QuizReminderService.hasPendingQuizReminderTap = false
                    navigateToChoosePracticeMode()
                }
                .task {
                    if QuizReminderService.hasPendingQuizReminderTap {
                        QuizReminderService.hasPendingQuizReminderTap = false
                        navigateToChoosePracticeMode()
                    }
                }
                .onChange(of: selectedTab) { _, newTab in
                    if newTab == .nameFaces || newTab == .people {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            isQuickInputExpanded = !(newTab == .nameFaces && nameFacesIsFeedMode)
                        }
                    }
                }
                .onChange(of: nameFacesIsFeedMode) { _, inFeedMode in
                    guard selectedTab == .nameFaces else { return }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        isQuickInputExpanded = !inFeedMode
                    }
                }
                .safeAreaInset(edge: .top) {
                    OfflineBannerView(
                        isOffline: isOffline,
                        isDismissed: offlineBannerDismissed,
                        onDismiss: { offlineBannerDismissed = true }
                    )
                }
                .safeAreaInset(edge: .bottom) {
                    quickInputSection
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .overlay {
                    loadingOverlay
                }
                .toolbar {
                    toolbarContent
                }
                .toolbarBackground(.hidden)
                .offlineActionAlert(showOfflineAlert: $showOfflineActionAlert)
                .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItem, matching: .images)
                .sheet(isPresented: $showDeletedView) {
                    DeletedView()
                }
                .sheet(isPresented: $showBulkAddFaces) {
                    BulkAddFacesView(contactsContext: modelContext)
                        .modelContainer(BatchModelContainer.shared)
                }
                .sheet(item: $contactForDateEdit) { contact in
                    CustomDatePicker(contact: contact, onRecordUndo: pushMovementUndoEntry)
                }
                .sheet(item: $groupForDateEdit, onDismiss: { groupForDateEdit = nil }) { group in
                    let primary = group.contacts.first ?? group.parsedContacts.first
                    let others = (group.contacts + group.parsedContacts).filter { primary != nil && $0.id != primary!.id }
                    if let primary = primary {
                        CustomDatePicker(contact: primary, additionalContactsToApply: others.isEmpty ? nil : others, onRecordUndo: pushMovementUndoEntry)
                    }
                }
                .sheet(isPresented: $showGroupTagPicker) {
                    TagPickerView(mode: .groupApply { tag in
                        applyGroupTagChange(tag)
                    })
                }
                .sheet(isPresented: $showManageTags) {
                    TagPickerView(mode: .manage)
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $showQuickNotesFeed) {
                    QuickNotesFeedView()
                }
                .alert("Exit Quiz?", isPresented: $showExitQuizConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Exit", role: .destructive) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            showQuizView = false
                        }
                    }
                } message: {
                    Text("You can resume this quiz later from where you left off.")
                }
                .navigationDestination(for: UUID.self) { uuid in
                    if let contact = contacts.first(where: { $0.uuid == uuid }) {
                        ContactDetailsView(contact: contact, onBack: {
                            if !contactPathIds.isEmpty { contactPathIds.removeLast() }
                        })
                    }
                }
        }
    }
    
    // MARK: - Content Sections

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            switch selectedTab {
            case .people:
                if let contact = selectedContact {
                    contactDetailContent(contact: contact)
                } else {
                    listAndPhotosContent
                }
            case .practice:
                PracticeTabView(
                    contacts: contacts,
                    showQuizView: showQuizView,
                    selectedQuizType: selectedQuizType,
                    quizResetTrigger: quizResetTrigger,
                    onSelectQuiz: {
                        selectedQuizType = $0
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            showQuizView = true
                        }
                    },
                    onQuizComplete: {
                        QuizReminderService.shared.maybeRequestPermissionOnQuizExit()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            showQuizView = false
                        }
                        quizResetTrigger = UUID()
                        selectedQuizType = nil
                    },
                    onClose: {
                        selectedTab = .people
                    }
                )
            case .nameFaces:
                NameFacesFeedCombinedView(
                    isInFeedMode: $nameFacesIsFeedMode,
                    onDismiss: {
                        faceNamingInitialDate = nil
                        selectedTab = .people
                    },
                    initialScrollDate: faceNamingInitialDate,
                    bottomBarHeight: tabBarHeight
                )
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selectedTab)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selectedContact != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showQuizView)
    }
    
    @ViewBuilder
    private func contactDetailContent(contact: Contact) -> some View {
        ContactDetailsView(contact: contact, onBack: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                selectedContact = nil
            }
        })
        .transition(.move(edge: .trailing))
        .zIndex(3)
    }
    
    @ViewBuilder
    private var listAndPhotosContent: some View {
        listContent
            .opacity(showInlinePhotoPicker || showFullPhotoGrid ? 0 : 1)
            .offset(y: showInlinePhotoPicker || showFullPhotoGrid ? -16 : 0)
            .allowsHitTesting(!showInlinePhotoPicker && !showFullPhotoGrid)
            .zIndex(0)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showInlinePhotoPicker)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showFullPhotoGrid)

        if allowPhotoDependentViews {
            inlinePhotoPickerContent
            if let payload = fullPhotoGridPayload {
                fullPhotoGridInlineView(payload: payload)
            }
        }
    }
    
    @ViewBuilder
    private var inlinePhotoPickerContent: some View {
        // Important for memory: don't mount the photo grid until the user actually opens it.
        // Keeping a hidden UICollectionView alive will still prefetch/decode/cache images in the background.
        if showInlinePhotoPicker {
            PhotosInlineView(contactsContext: modelContext, isVisible: true) { image, date in
                print("✅ [ContentView] Photo picked from inline view")
                pickedImageForBatch = image
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    showInlinePhotoPicker = false
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(showFullPhotoGrid ? 0 : 1)
        }
    }
    
    @ViewBuilder
    private var quickInputSection: some View {
        QuickInputBottomBar(
            selectedTab: $selectedTab,
            isQuickInputExpanded: $isQuickInputExpanded,
            canShowQuickInput: !showQuizView && !(selectedTab == .nameFaces && nameFacesIsFeedMode),
            showNameFacesButton: selectedTab != .nameFaces,
            onNameFacesTap: {
                faceNamingInitialDate = nil
                selectedTab = .nameFaces
            }
        ) {
            QuickInputView(
                parsedContacts: $parsedContacts,
                selectedContact: $selectedContact,
                onQuizTap: { selectedTab = .practice },
                onNameFacesTap: {
                    faceNamingInitialDate = nil
                    selectedTab = .nameFaces
                },
                showQuizButton: selectedTab != .practice,
                showNameFacesButton: selectedTab != .nameFaces,
                faceDetectionViewModel: fullPhotoGridFaceViewModel, onFaceSelected: { handleFaceSelectedFromCarousel(index: $0) }, onPhotoPicked: { image, date in
                    print("📸 [ContentView] Photo fallback - opening bulk face view")
                    pickedImageForBatch = image
                }, inlineInBar: true, cameraInSeparateBubble: true, faceNamingMode: selectedTab == .nameFaces
            )
            .id(quickInputResetID)
        }
    }
    
    @ViewBuilder
    private var loadingOverlay: some View {
        if isLoading {
            LoadingOverlay(message: "Loading…")
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !showQuizView, selectedContact == nil, contactPathIds.isEmpty {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                menuButton
            }
        }
    }
    
    @ViewBuilder
    private var menuButton: some View {
        Menu {
            if !movementUndoStack.isEmpty {
                Button {
                    performMovementUndo()
                } label: {
                    Label(String(localized: "contacts.undo.move"), systemImage: "arrow.uturn.backward")
                }
                Divider()
            }
            
            quickNotesButton
            
            Divider()
            
            deletedButton

            Divider()

            settingsButton

            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
                limitedLibraryButton
            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }
    
    // MARK: - Menu Buttons
    
    @ViewBuilder
    private var quickNotesButton: some View {
        Button {
            showQuickNotesFeed = true
        } label: {
            Label("Quick Notes", systemImage: "note.text")
        }
    }
    
    @ViewBuilder
    private var deletedButton: some View {
        Button {
            showDeletedView = true
        } label: {
            Label("Deleted", systemImage: "trash")
        }
    }
    
    @ViewBuilder
    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Label("Settings", systemImage: "gearshape")
        }
    }
    
    @ViewBuilder
    private var limitedLibraryButton: some View {
        Button {
            presentLimitedLibraryPicker()
        } label: {
            Label("Manage Photos Selection", systemImage: "plus.circle")
        }
    }
    
    // MARK: - Full Photo Grid View Builder
    
    @ViewBuilder
    private func fullPhotoGridInlineView(payload: PhotosSheetPayload) -> some View {
        PhotosFullGridInlineView(
            scope: payload.scope,
            contactsContext: modelContext,
            initialScrollDate: payload.initialScrollDate,
            faceDetectionViewModel: $fullPhotoGridFaceViewModel,
            onPhotoPicked: { image, date in
                print("✅ [ContentView] Photo picked from full grid inline view")
                pickedImageForBatch = image
                closeFullPhotoGrid()
            },
            onDismiss: {
                closeFullPhotoGrid()
            },
            attemptQuickAssign: attemptQuickAssignClosure()
        )
        .opacity(showFullPhotoGrid ? 1 : 0)
        .offset(y: showFullPhotoGrid ? 0 : 32)
        .allowsHitTesting(showFullPhotoGrid)
        .zIndex(2)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showFullPhotoGrid)
    }
    
    // MARK: - Event Handlers
    
    private func handlePickedImageChange(_ newImage: UIImage?) {
        if let image = newImage {
            showBulkAddFacesWithSeed(image: image, date: Date()) {
                pickedImageForBatch = nil
            }
        }
    }
    
    private func handleQuickInputHeightChange(_ height: CGFloat) {
        withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
            bottomInputHeight = height
        }
    }
    
    private func attemptQuickAssignClosure() -> ((UIImage, Date?) async -> Bool) {
        return { [modelContext, selectedContact] image, date in
            guard let contact = selectedContact else {
                return false
            }
            guard let cgImage = image.cgImage else {
                return false
            }

            let observations: [VNFaceObservation]
            do {
                let request = VNDetectFaceRectanglesRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try handler.perform([request])
                observations = (request.results as? [VNFaceObservation]) ?? []
            } catch {
                print("❌ [ContentView] Face detection failed: \(error)")
                return false
            }

            guard observations.count == 1, let face = observations.first else {
                print("📸 [ContentView] Auto-assign not applicable. Faces: \(observations.count)")
                return false
            }

            let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            let fullRect = CGRect(origin: .zero, size: imageSize)
            let scaleFactor: CGFloat = 1.8
            let bb = face.boundingBox
            let scaledBox = CGRect(
                x: bb.origin.x * imageSize.width - (bb.width * imageSize.width * (scaleFactor - 1)) / 2,
                y: (1 - bb.origin.y - bb.height) * imageSize.height - (bb.height * imageSize.height * (scaleFactor - 1)) / 2,
                width: bb.width * imageSize.width * scaleFactor,
                height: bb.height * imageSize.height * scaleFactor
            ).integral
            let clipped = scaledBox.intersection(fullRect)
            guard !clipped.isNull && !clipped.isEmpty, let cropped = cgImage.cropping(to: clipped) else {
                print("📸 [ContentView] Crop failed")
                return false
            }
            let faceImage = UIImage(cgImage: cropped)

            await MainActor.run {
                contact.photo = jpegDataForStoredContactPhoto(faceImage)
                ImageAccessibleBackground.updateContactPhotoGradient(contact, image: faceImage)
                do {
                    try modelContext.save()
                    print("✅ [ContentView] Auto-assigned single face to \(contact.name ?? "contact")")
                } catch {
                    StorageMonitor.reportIfENOSPC(error)
                    print("❌ [ContentView] Save failed: \(error)")
                }
            }

            return true
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleFaceSelectedFromCarousel(index: Int) {
        guard let viewModel = fullPhotoGridFaceViewModel,
              index >= 0,
              index < viewModel.faces.count else { return }
        
        let faceImage = viewModel.faces[index].image
        pickedImageForBatch = faceImage
    }
    
    private func openFullPhotoGrid(scope: PhotosPickerScope, initialScrollDate: Date?) {
        let payload = PhotosSheetPayload(scope: scope, initialScrollDate: initialScrollDate)
        fullPhotoGridPayload = payload
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            showFullPhotoGrid = true
        }
        
        print("🔵 [ContentView] Opening full photo grid with scope: \(scope)")
        if let date = initialScrollDate {
            print("🔵 [ContentView] Initial scroll date: \(date)")
        }
    }
    
    private func closeFullPhotoGrid() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            showFullPhotoGrid = false
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            fullPhotoGridPayload = nil
            fullPhotoGridFaceViewModel = nil
        }
    }

    private func combine(date: Date, withTimeFrom timeSource: Date) -> Date {
        let cal = Calendar.current
        let dateComps = cal.dateComponents([.year, .month, .day], from: date)
        let timeComps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: timeSource)
        var merged = DateComponents()
        merged.year = dateComps.year
        merged.month = dateComps.month
        merged.day = dateComps.day
        merged.hour = timeComps.hour
        merged.minute = timeComps.minute
        merged.second = timeComps.second
        merged.nanosecond = timeComps.nanosecond
        return cal.date(from: merged) ?? date
    }

    private func bottomMostID() -> PersistentIdentifier? {
        if let lastGroup = groups.last {
            if let id = lastGroup.parsedContacts.last?.id {
                return id
            }
            if let id = lastGroup.contacts.last?.id {
                return id
            }
        }
        return contacts.last?.id ?? parsedContacts.last?.id
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let id = bottomMostID() {
            withAnimation(nil) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    /// Call on main queue when CoreData+CloudKit posts WillResetSync. Clears model-backed state so no view holds invalidated Tag/Contact references. Use with .receive(on: DispatchQueue.main).
    private func handleCloudKitMirroringWillResetSync() {
        selectedTag = nil
        groupForTagEdit = nil
        groupForDateEdit = nil
        selectedContact = nil
        contactForDateEdit = nil
        showGroupTagPicker = false
        showManageTags = false
        faceNamingInitialDate = nil
        showDeletedView = false
        showBulkAddFaces = false
    }

    /// Switches to the practice tab and shows the choose-practice-mode view (QuizMenuView). Called when the user taps the quiz reminder notification.
    private func navigateToChoosePracticeMode() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            selectedTab = .practice
            showQuizView = false
            selectedQuizType = nil
        }
    }

    private func tagDateOptions() -> [(date: Date, tags: String)] {
        if cloudKitResetCoordinator?.isSyncResetInProgress == true { return [] }
        return groups
            .filter { !$0.isLongAgo }
            .compactMap { group in
                let names = group.contacts.flatMap(\.tagNames)
                let unique = Array(Set(names)).sorted {
                    $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                }
                guard !unique.isEmpty else { return nil }
                return (date: group.date, tags: unique.joined(separator: ", "))
            }
            .sorted { $0.date > $1.date }
    }
    
    private func applyGroupTagChange(_ tag: Tag) {
        guard let group = groupForTagEdit else {
            showGroupTagPicker = false
            return
        }
        for c in group.contacts {
            c.tags = [tag]
        }
        for c in group.parsedContacts {
            c.tags = [tag]
        }
        do {
            try modelContext.save()
        } catch {
            StorageMonitor.reportIfENOSPC(error)
            print("Save failed: \(error)")
        }
        showGroupTagPicker = false
        groupForTagEdit = nil
    }

    private func deleteAllEntries(in group: contactsGroup) {
        let idsToRemove = Set(group.parsedContacts.map { ObjectIdentifier($0) })
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            parsedContacts.removeAll { idsToRemove.contains(ObjectIdentifier($0)) }
        }

        for c in group.contacts {
            c.isArchived = true
            c.archivedDate = Date()
        }
        do {
            try modelContext.save()
        } catch {
            StorageMonitor.reportIfENOSPC(error)
            print("Save failed: \(error)")
        }
    }
    
    // MARK: - Movement undo
    
    private func snapshot(for contact: Contact) -> ContactMovementSnapshot {
        let tagNames: [String] = (cloudKitResetCoordinator?.isSyncResetInProgress == true)
            ? []
            : contact.tagNames
        return ContactMovementSnapshot(
            uuid: contact.uuid,
            isMetLongAgo: contact.isMetLongAgo,
            timestamp: contact.timestamp,
            tagNames: tagNames
        )
    }
    
    private func pushMovementUndoEntry(_ snapshots: [ContactMovementSnapshot]) {
        guard !snapshots.isEmpty else { return }
        movementUndoStack.append(snapshots)
        if movementUndoStack.count > maxMovementUndoStackSize {
            movementUndoStack.removeFirst()
        }
    }
    
    private func performMovementUndo() {
        guard !movementUndoStack.isEmpty else { return }
        let entry = movementUndoStack.removeLast()
        var didChangePersisted = false
        var didChangeParsed = false
        for s in entry {
            if let c = contacts.first(where: { $0.uuid == s.uuid }) {
                c.isMetLongAgo = s.isMetLongAgo
                c.timestamp = s.timestamp
                if s.tagNames.isEmpty {
                    c.tags = nil
                } else {
                    c.tags = s.tagNames.compactMap { Tag.fetchOrCreate(named: $0, in: modelContext) }
                }
                didChangePersisted = true
                continue
            }
            if let p = parsedContacts.first(where: { $0.uuid == s.uuid }) {
                p.isMetLongAgo = s.isMetLongAgo
                p.timestamp = s.timestamp
                if s.tagNames.isEmpty {
                    p.tags = nil
                } else {
                    p.tags = s.tagNames.compactMap { Tag.fetchOrCreate(named: $0, in: modelContext) }
                }
                didChangeParsed = true
            }
        }
        if didChangePersisted {
            do {
                try modelContext.save()
            } catch {
                StorageMonitor.reportIfENOSPC(error)
                print("Undo save failed: \(error)")
            }
        }
        if didChangeParsed {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                parsedContacts = parsedContacts
            }
        }
    }

    private func handleDrop(_ records: [ContactDragRecord], to group: contactsGroup) {
        var didChangePersisted = false
        var parsedContactsChanged = false
        var undoSnapshots: [ContactMovementSnapshot] = []

        let destTagNames: [String] = (cloudKitResetCoordinator?.isSyncResetInProgress == true)
            ? []
            : (group.contacts + group.parsedContacts).flatMap(\.tagNames)
        let uniqueDestTags = Array(Set(destTagNames)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let chosenTagName = uniqueDestTags.count == 1 ? uniqueDestTags.first : nil
        let chosenTag = chosenTagName.flatMap { Tag.fetchOrCreate(named: $0, in: modelContext) }

        for record in records {
            if let persisted = contacts.first(where: { $0.uuid == record.uuid }) {
                undoSnapshots.append(snapshot(for: persisted))
                if group.isLongAgo {
                    persisted.isMetLongAgo = true
                } else {
                    persisted.isMetLongAgo = false
                    persisted.timestamp = combine(date: group.date, withTimeFrom: persisted.timestamp)
                }
                if let tag = chosenTag {
                    persisted.tags = [tag]
                }
                didChangePersisted = true
                continue
            }

            if let parsed = parsedContacts.first(where: { $0.uuid == record.uuid }) {
                undoSnapshots.append(snapshot(for: parsed))
                if group.isLongAgo {
                    parsed.isMetLongAgo = true
                } else {
                    parsed.isMetLongAgo = false
                    parsed.timestamp = combine(date: group.date, withTimeFrom: parsed.timestamp)
                }
                if let tag = chosenTag {
                    parsed.tags = [tag]
                }
                parsedContactsChanged = true
                continue
            }
        }

        pushMovementUndoEntry(undoSnapshots)

        if didChangePersisted {
            do {
                try modelContext.save()
            } catch {
                StorageMonitor.reportIfENOSPC(error)
            }
        }
        
        if parsedContactsChanged {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                parsedContacts = parsedContacts
            }
        }
    }
}

private extension ContentView {
    func showBulkAddFacesWithSeed(image: UIImage, date: Date, completion: (() -> Void)? = nil) {
        let root = UIHostingController(
            rootView: BulkAddFacesView(contactsContext: modelContext, initialImage: image, initialDate: date)
                .modelContainer(BatchModelContainer.shared)
        )
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let rootVC = window.rootViewController {
            root.modalPresentationStyle = .formSheet
            rootVC.present(root, animated: true) {
                completion?()
            }
        } else {
            completion?()
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func presentLimitedLibraryPicker() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let rootViewController = window.rootViewController {
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: rootViewController)
        }
    }
}

// MARK: - Extracted Views to reduce type-checking complexity

private struct GroupSectionView: View {
    let group: contactsGroup
    let isLast: Bool
    /// When true, show date-only title to avoid reading Tag names (e.g. during CloudKit mirroring reset).
    let useSafeTitle: Bool
    let onImport: () -> Void
    let onEditDate: () -> Void
    let onEditTag: () -> Void
    let onRenameTag: () -> Void
    let onDeleteAll: () -> Void
    let onChangeDateForContact: (Contact) -> Void
    let onTapHeader: () -> Void
    let onDropRecords: ([ContactDragRecord]) -> Void

    @State private var isTargeted = false
    
    var body: some View {
        Section {
            VStack(spacing: 0) {
                header
                LazyVGrid(columns: Array(repeating: GridItem(spacing: 10), count: 4), spacing: 10) {
                    ForEach(group.contacts) { contact in
                        ContactTile(contact: contact, onChangeDate: {
                            onChangeDateForContact(contact)
                        })
                    }

                    ForEach(group.parsedContacts) { contact in
                        ParsedContactTile(contact: contact)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: AnyTransition(.opacity).combined(with: AnyTransition.scale(scale: 0.98))
                            ))
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.9), value: group.parsedContacts.count)
                }
                .padding(.horizontal)
                .padding(.bottom, isLast ? 0 : 16)
            }
            .contentShape(.rect)
            .dropDestination(for: ContactDragRecord.self) { items, _ in
                guard !items.isEmpty else { return false }
                onDropRecords(items)
                return true
            } isTargeted: { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isTargeted = hovering
                }
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 3)
                        .padding(.horizontal)
                        .padding(.bottom, isLast ? 0 : 16)
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        let content = VStack(alignment: .leading) {
            HStack {
                Text(useSafeTitle ? group.dateOnlyTitle : group.title)
                    .font(.title)
                    .bold()
                Spacer()
            }
            .padding(.leading)
            .padding(.trailing, 14)
            Text(group.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(.bottom, 12)
        .contentShape(.rect)

        if group.isLongAgo {
            content
        } else {
            content
                .onTapGesture {
                    onTapHeader()
                }
                .contextMenu {
                    Button {
                        onImport()
                    } label: {
                        Label("Import Photos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        onEditDate()
                    } label: {
                        Label("Change Date", systemImage: "calendar")
                    }
                    Button {
                        onEditTag()
                    } label: {
                        Label("Tag All in Group...", systemImage: "tag")
                    }
                    Button(role: .destructive) {
                        onDeleteAll()
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                }
        }
    }
}

private struct ContactTile: View {
    let contact: Contact
    @Environment(\.modelContext) private var modelContext
    var onChangeDate: (() -> Void)?
    var showNavigationTip: Bool = false
    
    var body: some View {
        NavigationLink(value: contact.uuid) {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack{
                    if !contact.photo.isEmpty, let uiImage = UIImage(data: contact.photo) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .scaleEffect(1.22)
                            .frame(width: size.width, height: size.height)
                            .clipped()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                        
                        LinearGradient(gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.0), .black.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
                    } else {
                        ZStack {
                            RadialGradient(
                                colors: [
                                    Color(uiColor: .secondarySystemBackground),
                                    Color(uiColor: .tertiarySystemBackground)
                                ],
                                center: .center,
                                startRadius: 5,
                                endRadius: size.width * 0.7
                            )
                            
                            Color.clear
                                .frame(width: size.width, height: size.height)
                                .liquidGlass(in: RoundedRectangle(cornerRadius: 10), stroke: true)
                        }
                    }
                    
                    VStack {
                        Spacer()
                        Text(contact.name ?? "")
                            .font(.footnote)
                            .bold()
                            .foregroundColor( contact.photo.isEmpty ? Color(uiColor: .label).opacity(0.8) : Color(uiColor: .white).opacity(0.8)
                            )
                            .padding(.bottom, 6)
                            .padding(.horizontal, 6)
                            .multilineTextAlignment(.center)
                            .lineSpacing(-2)
                    }
                }
            }
            .aspectRatio(1.0, contentMode: .fit)
            .contentShape(.rect)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.3)
                    .scaleEffect(phase.isIdentity ? 1 : 0.9)
            }
        }
        .popoverTip(ContactNavigationTip(), arrowEdge: .top)
        .draggable(ContactDragRecord(uuid: contact.uuid)) {
            Text(contact.name ?? "Contact")
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .contextMenu {
            Button {
                onChangeDate?()
            } label: {
                Label("Change Date", systemImage: "calendar")
            }

            Button(role: .destructive) {
                contact.isArchived = true
                contact.archivedDate = Date()
                do {
                    try modelContext.save()
                } catch {
                    print("Save failed: \(error)")
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct ParsedContactTile: View {
    let contact: Contact
    
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack{
                if !contact.photo.isEmpty, let uiImage = UIImage(data: contact.photo) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(1.22)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .background(Color(uiColor: .black).opacity(0.05))
                } else {
                    ZStack {
                        RadialGradient(
                            colors: [
                                Color(uiColor: .secondarySystemBackground),
                                Color(uiColor: .tertiarySystemBackground)
                            ],
                            center: .center,
                            startRadius: 5,
                            endRadius: size.width * 0.7
                        )
                        
                        Color.clear
                            .frame(width: size.width, height: size.height)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 10), stroke: true)
                    }
                }
                
                VStack {
                    Spacer()
                    Text(contact.name ?? "")
                        .font(.footnote)
                        .bold()
                        .foregroundColor(UIImage(data: contact.photo) != UIImage() ? Color(uiColor: .label).opacity(0.8) : Color(uiColor: .white).opacity(0.8)
                        )
                        .padding(.bottom, 6)
                        .padding(.horizontal, 6)
                        .multilineTextAlignment(.center)
                        .lineSpacing(-2)
                }
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .contentShape(.rect)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .draggable(ContactDragRecord(uuid: contact.uuid)) {
            Text(contact.name ?? "Contact")
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear {
            print("📋 [ParsedContactTile] Showing: \(contact.name ?? "unnamed") with UUID: \(contact.uuid)")
        }
    }
}

private struct BottomInsetHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview("List") {
        ContentView().modelContainer(for: [Contact.self, Note.self, Tag.self], inMemory: true)
}

#Preview("Contact Detail") {
    ModelContainerPreview(ModelContainer.sample) {
        NavigationStack{
            ContactDetailsView(contact:.ross)
        }
    }
}
