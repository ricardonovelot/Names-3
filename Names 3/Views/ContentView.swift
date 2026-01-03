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
    @State private var hasPendingQuickNoteInput = false
    @State private var quickInputResetID = 0
    @State private var showAllGroupTagDates = false
    @State private var contactForDateEdit: Contact?
    @State private var bottomInputHeight: CGFloat = 0
    
    private struct PhotosSheetPayload: Identifiable, Hashable {
        let id = UUID()
        let scope: PhotosPickerScope
    }
    @State private var photosSheet: PhotosSheetPayload?
    @State private var pickedImageForBatch: UIImage?

    // Group contacts by the day of their timestamp, with a special "Met long ago" group at the top
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
                                photosSheet = PhotosSheetPayload(scope: .day(group.date))
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
                                photosSheet = PhotosSheetPayload(scope: .day(group.date))
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
                    ContactDetailsView(contact: contact)
                        .transition(.move(edge: .trailing))
                        .zIndex(2)
                } else {
                    listContent
                        .opacity(showInlineQuickNotes ? 0 : 1)
                        .offset(y: showInlineQuickNotes ? -16 : 0)
                        .allowsHitTesting(!showInlineQuickNotes)
                        .zIndex(0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showInlineQuickNotes)

                    QuickNotesInlineView()
                        .opacity(showInlineQuickNotes ? 1 : 0)
                        .offset(y: showInlineQuickNotes ? 0 : 28)
                        .allowsHitTesting(showInlineQuickNotes)
                        .zIndex(1)
                        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showInlineQuickNotes)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: selectedContact != nil)
            // Ensure background fills under keyboard and safe areas—no white seams
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
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
                    selectedContact: $selectedContact
                ) {
                    photosSheet = PhotosSheetPayload(scope: .all)
                } onQuickNoteAdded: {
                    hasPendingQuickNoteInput = false
                } onQuickNoteDetected: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        showInlineQuickNotes = true
                    }
                    hasPendingQuickNoteInput = true
                } onQuickNoteCleared: {
                    hasPendingQuickNoteInput = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        showInlineQuickNotes = false
                    }
                }
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
            .sheet(item: $photosSheet) { payload in
                PhotosDayPickerHost(
                    scope: payload.scope,
                    contactsContext: modelContext,
                    initialScrollDate: selectedContact?.timestamp,
                    onPick: { image, date in
                        print("✅ [ContentView] onPick called - dismissing photos sheet")
                        pickedImageForBatch = image
                        photosSheet = nil
                    }
                )
                .onAppear {
                    if let date = selectedContact?.timestamp {
                        print("🔵 [ContentView] Opening photo picker with scroll date: \(date) for contact: \(selectedContact?.name ?? "unknown")")
                    } else {
                        print("🔵 [ContentView] Opening photo picker without scroll date")
                    }
                }
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

    // Helper to compute the bottom-most visible item ID, matching list order
    private func bottomMostID() -> PersistentIdentifier? {
        if let lastGroup = groups.last {
            if let id = lastGroup.parsedContacts.last?.id {
                return id
            }
            if let id = lastGroup.contacts.last?.id {
                return id
            }
        }
        // Fallbacks if groups are empty or have no items
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
    
    var body: some View {
        Section {
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
                            removal: AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.98))
                        ))
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: group.parsedContacts.count)
            }
            .padding(.horizontal)
            .padding(.bottom, isLast ? 0 : 16)
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
                        Label("Apply Tag", systemImage: "tag")
                    }
                    Button {
                        onRenameTag()
                    } label: {
                        Label("Manage Tags", systemImage: "tag.square")
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
                    Image(uiImage: UIImage(data: contact.photo) ?? UIImage())
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                    
                    if !contact.photo.isEmpty {
                        LinearGradient(gradient: Gradient(colors: [.black.opacity(0.0), .black.opacity(0.0), .black.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
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
            .frame(height: 88)
            .contentShape(.rect)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .scrollTransition { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0.3)
                    .scaleEffect(phase.isIdentity ? 1 : 0.9)
            }
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
                Image(uiImage: UIImage(data: contact.photo) ?? UIImage())
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .background(Color(uiColor: .black).opacity(0.05))
                
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
        .frame(height: 88)
        .contentShape(.rect)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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