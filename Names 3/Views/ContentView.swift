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
    
    @Query(filter: #Predicate<Contact> { $0.isArchived == false })
    private var contacts: [Contact]
    @State private var parsedContacts: [Contact] = []
    @State private var selectedContact: Contact?
    
    @State private var selectedItem: PhotosPickerItem?
    
    @State private var isAtBottom = true
    private let dragThreshold: CGFloat = 100
    
    @State private var date = Date()

    @State private var showPhotosPicker = false
    @State private var showQuizView = false
    @State private var showRegexHelp = false
    @State private var showBulkAddFaces = false
    @State private var showGroupPhotos = false
    
    @State private var name = ""
    @State private var hashtag = ""
    
    @State private var showGroupDatePicker = false
    @State private var tempGroupDate = Date()

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
    @State private var showHomeView = false
    @State private var homeTabSelection: AppTab = .home
    @State private var fullPhotoGridFaceViewModel: FaceDetectionViewModel? = nil
    @State private var showSettings = false
    
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
    
    @ViewBuilder
    private var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(groups) { group in
                        GroupSectionView(
                            group: group,
                            isLast: group.id == groups.last?.id,
                            onImport: {
                                guard !group.isLongAgo else { return }
                                openFullPhotoGrid(scope: .all, initialScrollDate: group.date)
                            },
                            onEditDate: {
                                guard !group.isLongAgo else { return }
                                groupForDateEdit = group
                                Task {
                                    try? await Task.sleep(for: .milliseconds(150))
                                    tempGroupDate = group.date
                                    showGroupDatePicker = true
                                }
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
                                openFullPhotoGrid(scope: .all, initialScrollDate: group.date)
                            },
                            onDropRecords: { records in
                                handleDrop(records, to: group)
                            }
                        )
                    }
                }
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                if let contact = selectedContact {
                    ContactDetailsView(contact: contact, onBack: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            selectedContact = nil
                        }
                    })
                        .transition(.move(edge: .trailing))
                        .zIndex(3)
                } else {
                    listContent
                        .opacity(showInlineQuickNotes || showInlinePhotoPicker || showFullPhotoGrid ? 0 : 1)
                        .offset(y: showInlineQuickNotes || showInlinePhotoPicker || showFullPhotoGrid ? -16 : 0)
                        .allowsHitTesting(!showInlineQuickNotes && !showInlinePhotoPicker && !showFullPhotoGrid)
                        .zIndex(0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showInlineQuickNotes)
                        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showInlinePhotoPicker)
                        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showFullPhotoGrid)

                    QuickNotesInlineView()
                        .opacity(showInlineQuickNotes ? 1 : 0)
                        .offset(y: showInlineQuickNotes ? 0 : 28)
                        .allowsHitTesting(showInlineQuickNotes)
                        .zIndex(showFullPhotoGrid ? 0 : 1)
                        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showInlineQuickNotes)

                    PhotosInlineView(contactsContext: modelContext, isVisible: showInlinePhotoPicker) { image, date in
                        print("✅ [ContentView] Photo picked from inline view")
                        pickedImageForBatch = image
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            showInlinePhotoPicker = false
                        }
                    }
                    .opacity(showInlinePhotoPicker ? 1 : 0)
                    .offset(y: showInlinePhotoPicker ? 0 : 28)
                    .allowsHitTesting(showInlinePhotoPicker)
                    .zIndex(showInlineQuickNotes || showFullPhotoGrid ? 0 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showInlinePhotoPicker)
                    
                    if let payload = fullPhotoGridPayload {
                        fullPhotoGridInlineView(payload: payload)
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selectedContact != nil)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .onChange(of: pickedImageForBatch) { oldValue, newValue in
                if let image = newValue {
                    showBulkAddFacesWithSeed(image: image, date: Date()) {
                        pickedImageForBatch = nil
                    }
                }
            }
            .onPreferenceChange(TotalQuickInputHeightKey.self) { height in
                withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
                    bottomInputHeight = height
                }
            }
            .safeAreaInset(edge: .bottom) {
                QuickInputView(
                    mode: .people,
                    parsedContacts: $parsedContacts,
                    isQuickNotesActive: $showInlineQuickNotes,
                    selectedContact: $selectedContact,
                    onCameraTap: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            if showInlineQuickNotes { showInlineQuickNotes = false }
                            if showInlinePhotoPicker { showInlinePhotoPicker = false }
                            if showFullPhotoGrid { closeFullPhotoGrid() }
                        }
                        openFullPhotoGrid(scope: .all, initialScrollDate: nil)
                    },
                    onQuickNoteAdded: {
                        hasPendingQuickNoteInput = false
                    },
                    onQuickNoteDetected: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            if showInlinePhotoPicker { showInlinePhotoPicker = false }
                            if showFullPhotoGrid { closeFullPhotoGrid() }
                            showInlineQuickNotes = true
                        }
                        hasPendingQuickNoteInput = true
                    },
                    onQuickNoteCleared: {
                        hasPendingQuickNoteInput = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            showInlineQuickNotes = false
                        }
                    },
                    onInlinePhotosTap: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            if showInlineQuickNotes { showInlineQuickNotes = false }
                            if showFullPhotoGrid { closeFullPhotoGrid() }
                            showInlinePhotoPicker.toggle()
                        }
                    },
                    isInlinePhotosActive: { showInlinePhotoPicker },
                    faceDetectionViewModel: fullPhotoGridFaceViewModel,
                    onFaceSelected: { index in
                        handleFaceSelectedFromCarousel(index: index)
                    },
                    onPhotoPicked: { image, date in
                        print("📸 [ContentView] Photo fallback - opening bulk face view")
                        pickedImageForBatch = image
                    }
                )
                .id(quickInputResetID)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay {
                if isLoading {
                    LoadingOverlay(message: "Loading…")
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                        }) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            showDeletedView = true
                        } label: {
                            Label("Deleted", systemImage: "trash")
                        }
                        Button {
                            showGroupPhotos = true
                        } label: {
                            Label("Group Photos", systemImage: "person.3.sequence")
                        }
                        Button {
                            showQuizView = true
                        } label: {
                            Label("Faces Quiz", systemImage: "questionmark.circle")
                        }
                        Button {
                            showRegexHelp = true
                        } label: {
                            Label("Instructions", systemImage: "info.circle")
                        }

                        Divider()
                        
                        Button {
                            showManageTags = true
                        } label: {
                            Label("Groups & Places", systemImage: "tag")
                        }

                        Divider()

                        Button {
                            showHomeView = true
                        } label: {
                            Label("Recent", systemImage: "house")
                        }
                        
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }

                        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
                            Button {
                                presentLimitedLibraryPicker()
                            } label: {
                                Label("Manage Photos Selection", systemImage: "plus.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .fontWeight(.medium)
                            .liquidGlass(in: Capsule())
                    }
                }
            }
            .toolbarBackground(.hidden)
            
            .photosPicker(isPresented: $showPhotosPicker, selection: $selectedItem, matching: .images)
            .sheet(isPresented: $showQuizView) {
                QuizView(contacts: contacts)
            }
            .sheet(isPresented: $showRegexHelp) {
                RegexShortcutsView()
            }
            .sheet(isPresented: $showDeletedView) {
                DeletedView()
            }
            .sheet(isPresented: $showBulkAddFaces) {
                BulkAddFacesView(contactsContext: modelContext)
                    .modelContainer(BatchModelContainer.shared)
            }
            .sheet(isPresented: $showGroupPhotos) {
                GroupPhotosListView(contactsContext: modelContext)
                    .modelContainer(BatchModelContainer.shared)
            }
            .sheet(item: $contactForDateEdit) { contact in
                CustomDatePicker(contact: contact)
            }
            .sheet(isPresented: $showGroupTagPicker) {
                TagPickerView(mode: .groupApply { tag in
                    applyGroupTagChange(tag)
                })
            }
            .sheet(isPresented: $showManageTags) {
                TagPickerView(mode: .manage)
            }
            .sheet(isPresented: $showHomeView) {
                HomeView(tabSelection: $homeTabSelection)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
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
                contact.photo = faceImage.jpegData(compressionQuality: 0.92) ?? Data()
                do {
                    try modelContext.save()
                    print("✅ [ContentView] Auto-assigned single face to \(contact.name ?? "contact")")
                } catch {
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

    private func applyGroupDateChange() {
        if let group = groupForDateEdit {
            updateGroupDate(for: group, newDate: tempGroupDate)
        }
        showGroupDatePicker = false
        groupForDateEdit = nil
    }
    
    private func updateGroupDate(for group: contactsGroup, newDate: Date) {
        for c in group.contacts {
            c.isMetLongAgo = false
            c.timestamp = combine(date: newDate, withTimeFrom: c.timestamp)
        }
        for c in group.parsedContacts {
            c.isMetLongAgo = false
            c.timestamp = combine(date: newDate, withTimeFrom: c.timestamp)
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
    
    private func tagDateOptions() -> [(date: Date, tags: String)] {
        groups
            .filter { !$0.isLongAgo }
            .compactMap { group in
                let names = group.contacts
                    .flatMap { ($0.tags ?? []).compactMap { $0.name } }
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
            print("Save failed: \(error)")
        }
    }

    private func handleDrop(_ records: [ContactDragRecord], to group: contactsGroup) {
        var didChangePersisted = false
        var parsedContactsChanged = false

        let destTagNames = (group.contacts + group.parsedContacts)
            .flatMap { ($0.tags ?? []).compactMap { $0.name } }
        let uniqueDestTags = Array(Set(destTagNames)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let chosenTagName = uniqueDestTags.count == 1 ? uniqueDestTags.first : nil
        let chosenTag = chosenTagName.flatMap { Tag.fetchOrCreate(named: $0, in: modelContext) }

        for record in records {
            if let persisted = contacts.first(where: { $0.uuid == record.uuid }) {
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

        if didChangePersisted {
            try? modelContext.save()
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
                Text(group.title)
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
        .padding(.bottom, 4)
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
    
    var body: some View {
        NavigationLink {
            ContactDetailsView(contact: contact)
        } label: {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack{
                    if !contact.photo.isEmpty, let uiImage = UIImage(data: contact.photo) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
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