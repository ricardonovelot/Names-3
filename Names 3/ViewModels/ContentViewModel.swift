//
//  ContentViewModel.swift
//  Names 3
//
//  All mutable UI state and business logic for ContentView, extracted into
//  a dedicated @Observable view model. ContentView retains only @Query,
//  @Environment reads, and view-building responsibilities.
//
//  Mutating operations that require a ModelContext or SwiftData contacts receive
//  them as parameters — the view holds the environment and passes them in.
//

import SwiftUI
import SwiftData
import PhotosUI
import Vision
import Photos
import os

// MARK: - People Feed Filter

enum PeopleFeedFilter: Int, CaseIterable {
    case people = 0
    case peopleWithNotes = 1

    static let userDefaultsKey = "Names3.PeopleFeedFilter"
    static let migrationDoneKey = "Names3.PeopleFeedFilter.migrated"

    var title: String {
        switch self {
        case .people: return String(localized: "filter.people")
        case .peopleWithNotes: return String(localized: "filter.peopleWithNotes")
        }
    }

    var systemImage: String {
        switch self {
        case .people: return "person.2"
        case .peopleWithNotes: return "person.2.square.stack"
        }
    }
}

@MainActor
@Observable
final class ContentViewModel {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Names3",
        category: "ContentView"
    )

    // MARK: - Tab / Navigation

    var selectedTab: MainTab = .people

    var peopleFeedFilter: PeopleFeedFilter = {
        if UserDefaults.standard.bool(forKey: PeopleFeedFilter.migrationDoneKey) {
            let raw = UserDefaults.standard.integer(forKey: PeopleFeedFilter.userDefaultsKey)
            return PeopleFeedFilter(rawValue: raw) ?? .people
        }
        let stored = UserDefaults.standard.object(forKey: PeopleFeedFilter.userDefaultsKey) as? Int
        let migrated: PeopleFeedFilter
        if let s = stored {
            switch s {
            case 0: migrated = .peopleWithNotes
            case 1: migrated = .people
            case 2: migrated = .peopleWithNotes
            default: migrated = .people
            }
        } else {
            migrated = .people
        }
        UserDefaults.standard.set(migrated.rawValue, forKey: PeopleFeedFilter.userDefaultsKey)
        UserDefaults.standard.set(true, forKey: PeopleFeedFilter.migrationDoneKey)
        return migrated
    }() {
        didSet {
            UserDefaults.standard.set(peopleFeedFilter.rawValue, forKey: PeopleFeedFilter.userDefaultsKey)
        }
    }

    var selectedContact: Contact?
    /// Typed-erased navigation path so both UUID (contact) and ContactNoteNavigationTarget
    /// (contact + specific note) can coexist as destinations without a parallel stack.
    var contactPath: NavigationPath = NavigationPath()
    /// Preserved when switching away from People tab so we can restore contact details on return.
    var savedPeopleContactPath: NavigationPath = NavigationPath()
    /// True when contact details was pushed from the quick input (autocomplete or create).
    /// False when pushed by tapping a card in the feed.
    var contactNavigatedFromQuickInput: Bool = false

    // MARK: - Quick Input

    var isQuickInputExpanded = false
    var parsedContacts: [Contact] = []
    var hasPendingQuickNoteInput = false
    var quickInputResetID = 0

    // MARK: - Modal Flags

    var isLoading = false
    var showPhotosPicker = false
    var showQuizView = false
    var selectedQuizType: QuizType?
    var showBulkAddFaces = false
    var selectedItem: PhotosPickerItem?
    var showDeletedView = false
    var showInlineQuickNotes = false
    var showInlinePhotoPicker = false
    var showAllGroupTagDates = false
    var showSettings = false
    var showQuickNotesFeed = false
    var showExitQuizConfirmation = false
    var showOfflineActionAlert = false
    var showJournalNewEntrySheet = false
    var showPracticeSheet = false

    // MARK: - Date / Tag Sheet State

    var groupForDateEdit: ContactsGroup?
    var contactForDateEdit: Contact?
    var groupForTagEdit: ContactsGroup?
    var showManageTags = false
    var selectedTag: Tag?
    var newTagName: String = ""

    // MARK: - Layout Metrics

    var bottomInputHeight: CGFloat = 0
    var tabBarHeight: CGFloat = 0

    // MARK: - Photos Grid

    var fullPhotoGridFaceViewModel: FaceDetectionViewModel?
    var showFullPhotoGrid = false
    var fullPhotoGridPayload: PhotosSheetPayload?
    var pickedImageForBatch: UIImage?
    var allowPhotoDependentViews = false

    // MARK: - Feed / Face Naming

    var faceNamingInitialDate: Date?
    var photosIsFeedMode = true
    /// Increment to force feed to refresh (e.g. after tag change). SwiftUI may not detect in-place mutations.
    var feedRefreshTrigger: Int = 0

    // MARK: - Quiz

    var quizResetTrigger = UUID()

    // MARK: - Sync State

    var showInitialSyncState = true

    // MARK: - Banner Dismissal

    var offlineBannerDismissed = false
    var cellularBannerDismissed = false
    var storageBannerDismissed = false

    // MARK: - Movement Undo

    var movementUndoStack: [[ContactMovementSnapshot]] = []
    let maxMovementUndoStackSize = 50

    // MARK: - Async Contacts Load

    var asyncLoadedContacts: [Contact] = []
    var asyncLoadComplete = false

    // MARK: - Photos Sheet Payload

    struct PhotosSheetPayload: Identifiable, Hashable {
        let id = UUID()
        let scope: PhotosPickerScope
        let initialScrollDate: Date?

        init(scope: PhotosPickerScope, initialScrollDate: Date? = nil) {
            self.scope = scope
            self.initialScrollDate = initialScrollDate
        }
    }

    // MARK: - Contact Loading

    func loadContactsIfNeeded(container: ModelContainer?, mainContext: ModelContext) async {
        guard let container else {
            asyncLoadComplete = true
            return
        }
        asyncLoadedContacts = await FeedContactsLoader.loadContacts(
            container: container,
            mainContext: mainContext,
            fetchLimit: 500
        )
        asyncLoadComplete = true
    }

    func refreshContacts(container: ModelContainer, mainContext: ModelContext) {
        Task {
            asyncLoadedContacts = await FeedContactsLoader.loadContacts(
                container: container,
                mainContext: mainContext,
                fetchLimit: 500
            )
        }
    }

    // MARK: - Lifecycle

    func onMainContentAppear(
        groups: [ContactsGroup],
        storageMonitor: StorageMonitor?
    ) {
        LaunchProfiler.logCheckpoint("ContentView mainContent appeared")
        Self.logger.info("🚀 [Launch] Feed state: groups=\(groups.count)")
        if groups.isEmpty { storageMonitor?.refreshIfNeeded() }
        DispatchQueue.main.async { [self] in
            allowPhotoDependentViews = true
        }
    }

    func hideSyncStateAfterDelay() async {
        try? await Task.sleep(for: .seconds(120))
        showInitialSyncState = false
    }

    // MARK: - Banner Reset

    func handleConnectivityChange(isOffline: Bool) {
        if !isOffline { offlineBannerDismissed = false }
    }

    func handleCellularChange(usesCellular: Bool) {
        if !usesCellular { cellularBannerDismissed = false }
    }

    func handleStorageChange(isLow: Bool) {
        if !isLow { storageBannerDismissed = false }
    }

    // MARK: - Notification Navigation

    func handlePendingQuizReminderTap() {
        if QuizReminderService.hasPendingQuizReminderTap {
            QuizReminderService.hasPendingQuizReminderTap = false
            navigateToChoosePracticeMode()
        }
    }

    func navigateToChoosePracticeMode() {
        selectedTab = .people
        showQuizView = false
        selectedQuizType = nil
        showPracticeSheet = true
    }

    // MARK: - CloudKit Mirroring Reset

    /// Clears model-backed state so no view holds invalidated Tag/Contact references.
    /// Must be called when NSCloudKitMirroringDelegateWillResetSyncNotificationName fires.
    func handleCloudKitMirroringWillResetSync() {
        selectedTag = nil
        groupForTagEdit = nil
        groupForDateEdit = nil
        selectedContact = nil
        contactForDateEdit = nil
        showManageTags = false
        faceNamingInitialDate = nil
        showDeletedView = false
        showBulkAddFaces = false
    }

    // MARK: - Photos Grid

    func openFullPhotoGrid(scope: PhotosPickerScope, initialScrollDate: Date?) {
        let payload = PhotosSheetPayload(scope: scope, initialScrollDate: initialScrollDate)
        fullPhotoGridPayload = payload
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            showFullPhotoGrid = true
        }
        Self.logger.debug("Opening full photo grid, scope=\(String(describing: scope))")
    }

    func closeFullPhotoGrid() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            showFullPhotoGrid = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            fullPhotoGridPayload = nil
            fullPhotoGridFaceViewModel = nil
        }
    }

    // MARK: - Image Picked

    func handlePickedImageChange(_ newImage: UIImage?) -> UIImage? {
        newImage
    }

    // MARK: - Face from Carousel

    func handleFaceSelectedFromCarousel(index: Int) {
        guard let viewModel = fullPhotoGridFaceViewModel,
              index >= 0, index < viewModel.faces.count else { return }
        pickedImageForBatch = viewModel.faces[index].image
    }

    // MARK: - Quick Input Height

    func handleQuickInputHeightChange(_ height: CGFloat) {
        withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
            bottomInputHeight = height
        }
    }

    // MARK: - Tag Operations

    func applyGroupTagChange(_ tag: Tag, context: ModelContext) {
        guard let group = groupForTagEdit else { return }
        for c in group.contacts { c.tags = [tag] }
        for c in group.parsedContacts { c.tags = [tag] }
        do {
            try context.save()
        } catch {
            StorageMonitor.reportIfENOSPC(error)
            Self.logger.error("applyGroupTagChange save failed: \(error.localizedDescription)")
        }
        // Trigger feed refresh: SwiftUI may not detect in-place mutations on contacts.
        parsedContacts = parsedContacts
        asyncLoadedContacts = asyncLoadedContacts
        feedRefreshTrigger += 1
        groupForTagEdit = nil
    }

    // MARK: - Delete Group

    func deleteAllEntries(in group: ContactsGroup, context: ModelContext) {
        let idsToRemove = Set(group.parsedContacts.map { ObjectIdentifier($0) })
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            parsedContacts.removeAll { idsToRemove.contains(ObjectIdentifier($0)) }
        }
        for c in group.contacts {
            c.isArchived = true
            c.archivedDate = Date()
        }
        do {
            try context.save()
        } catch {
            StorageMonitor.reportIfENOSPC(error)
            Self.logger.error("deleteAllEntries save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Movement Undo

    func snapshot(
        for contact: Contact,
        isSyncResetInProgress: Bool
    ) -> ContactMovementSnapshot {
        let tagNames: [String] = isSyncResetInProgress ? [] : contact.tagNames
        return ContactMovementSnapshot(
            uuid: contact.uuid,
            isMetLongAgo: contact.isMetLongAgo,
            timestamp: contact.timestamp,
            tagNames: tagNames
        )
    }

    func pushMovementUndoEntry(_ snapshots: [ContactMovementSnapshot]) {
        guard !snapshots.isEmpty else { return }
        movementUndoStack.append(snapshots)
        if movementUndoStack.count > maxMovementUndoStackSize {
            movementUndoStack.removeFirst()
        }
    }

    func performMovementUndo(
        contacts: [Contact],
        context: ModelContext,
        isSyncResetInProgress: Bool
    ) {
        guard !movementUndoStack.isEmpty else { return }
        let entry = movementUndoStack.removeLast()
        var didChangePersisted = false
        var didChangeParsed = false

        for s in entry {
            if let c = contacts.first(where: { $0.uuid == s.uuid }) {
                applySnapshot(s, to: c, context: context, isSyncResetInProgress: isSyncResetInProgress)
                didChangePersisted = true
                continue
            }
            if let p = parsedContacts.first(where: { $0.uuid == s.uuid }) {
                applySnapshot(s, to: p, context: context, isSyncResetInProgress: isSyncResetInProgress)
                didChangeParsed = true
            }
        }

        if didChangePersisted {
            do {
                try context.save()
            } catch {
                StorageMonitor.reportIfENOSPC(error)
                Self.logger.error("Undo save failed: \(error.localizedDescription)")
            }
        }
        if didChangeParsed {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                parsedContacts = parsedContacts
            }
        }
    }

    private func applySnapshot(
        _ s: ContactMovementSnapshot,
        to contact: Contact,
        context: ModelContext,
        isSyncResetInProgress: Bool
    ) {
        contact.isMetLongAgo = s.isMetLongAgo
        contact.timestamp = s.timestamp
        if s.tagNames.isEmpty || isSyncResetInProgress {
            contact.tags = nil
        } else {
            contact.tags = s.tagNames.compactMap { Tag.fetchOrCreate(named: $0, in: context) }
        }
    }

    // MARK: - Drag & Drop

    func handleDrop(
        _ records: [ContactDragRecord],
        to group: ContactsGroup,
        contacts: [Contact],
        context: ModelContext,
        isSyncResetInProgress: Bool
    ) {
        let destTagNames: [String] = isSyncResetInProgress
            ? []
            : (group.contacts + group.parsedContacts).flatMap(\.tagNames)
        let uniqueDestTags = Array(Set(destTagNames)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        let chosenTag = (uniqueDestTags.count == 1 ? uniqueDestTags.first : nil)
            .flatMap { Tag.fetchOrCreate(named: $0, in: context) }

        var undoSnapshots: [ContactMovementSnapshot] = []
        var didChangePersisted = false
        var parsedContactsChanged = false

        for record in records {
            if let persisted = contacts.first(where: { $0.uuid == record.uuid }) {
                undoSnapshots.append(snapshot(for: persisted, isSyncResetInProgress: isSyncResetInProgress))
                moveContact(persisted, to: group, chosenTag: chosenTag)
                didChangePersisted = true
                continue
            }
            if let parsed = parsedContacts.first(where: { $0.uuid == record.uuid }) {
                undoSnapshots.append(snapshot(for: parsed, isSyncResetInProgress: isSyncResetInProgress))
                moveContact(parsed, to: group, chosenTag: chosenTag)
                parsedContactsChanged = true
            }
        }

        pushMovementUndoEntry(undoSnapshots)

        if didChangePersisted {
            do {
                try context.save()
            } catch {
                StorageMonitor.reportIfENOSPC(error)
                Self.logger.error("handleDrop save failed: \(error.localizedDescription)")
            }
        }
        if parsedContactsChanged {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                parsedContacts = parsedContacts
            }
        }
    }

    private func moveContact(_ contact: Contact, to group: ContactsGroup, chosenTag: Tag?) {
        if group.isLongAgo {
            contact.isMetLongAgo = true
        } else {
            contact.isMetLongAgo = false
            contact.timestamp = combine(date: group.date, withTimeFrom: contact.timestamp)
        }
        if let tag = chosenTag {
            contact.tags = [tag]
        }
    }

    // MARK: - Date Helper

    func combine(date: Date, withTimeFrom timeSource: Date) -> Date {
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

    // MARK: - Tag/Date Options

    func tagDateOptions(groups: [ContactsGroup], isSyncResetInProgress: Bool) -> [(date: Date, tags: String)] {
        guard !isSyncResetInProgress else { return [] }
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

    // MARK: - Auto-Assign Face

    /// Detects a single face in the image and assigns it to the currently selected contact.
    /// Returns `true` on success, `false` if detection found 0 or 2+ faces or the crop failed.
    func attemptQuickAssign(image: UIImage, context: ModelContext) async -> Bool {
        guard let contact = selectedContact,
              let cgImage = image.cgImage else { return false }

        let observations: [VNFaceObservation]
        do {
            let request = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])
            observations = request.results ?? []
        } catch {
            Self.logger.error("Face detection failed: \(error.localizedDescription)")
            return false
        }

        guard observations.count == 1, let face = observations.first else {
            Self.logger.debug("Auto-assign skipped: face count=\(observations.count)")
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
        guard !clipped.isNull, !clipped.isEmpty, let cropped = cgImage.cropping(to: clipped) else {
            Self.logger.warning("Auto-assign crop failed")
            return false
        }

        let faceImage = UIImage(cgImage: cropped)
        contact.photo = jpegDataForStoredContactPhoto(faceImage)
        ImageAccessibleBackground.updateContactPhotoGradient(contact, image: faceImage)
        do {
            try context.save()
            Self.logger.info("Auto-assigned face to \(contact.name ?? "contact")")
        } catch {
            StorageMonitor.reportIfENOSPC(error)
            Self.logger.error("Auto-assign save failed: \(error.localizedDescription)")
        }
        return true
    }
}
