//
//  UnifiedPeopleFeedView.swift
//  Names 3
//
//  Data types and SwiftUI wrapper for the unified People-tab feed, which shows
//  contacts and notes in the same date-grouped grid.
//
//  Design principle: meeting someone IS the first note about them.
//  Contacts render as the existing square photo+name cell (the "headline").
//  Notes render as the low-opacity photo + text overlay cell (the "annotation").
//  Both live in the same date section. Filter in the toolbar selects which
//  item types are visible.
//

import SwiftUI
import SwiftData

// MARK: - UnifiedFeedGroup

/// A date-bucketed group that holds both contacts and notes for the unified feed.
/// Mirrors the shape of `ContactsGroup` but also carries `notes`.
struct UnifiedFeedGroup: Identifiable, Hashable {

    var id: String {
        isLongAgo
            ? "long-ago"
            : "day-\(Calendar.current.startOfDay(for: date).timeIntervalSince1970)"
    }

    let date: Date
    let contacts: [Contact]
    let parsedContacts: [Contact]
    let notes: [Note]
    let isLongAgo: Bool

    /// True when the section has at least one contact, meaning the header context menu applies.
    var hasContacts: Bool { !contacts.isEmpty || !parsedContacts.isEmpty }

    // MARK: Header display — mirrors ContactsGroup logic exactly

    var title: String {
        if isLongAgo { return NSLocalizedString("Met long ago", comment: "") }
        let tagNames = contacts.flatMap(\.tagNames)
        let uniqueTags = Array(Set(tagNames)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return uniqueTags.isEmpty ? dateOnlyTitle : uniqueTags.joined(separator: ", ")
    }

    var dateOnlyTitle: String {
        if isLongAgo { return NSLocalizedString("Met long ago", comment: "") }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM dd"
        return formatter.string(from: date)
    }

    var subtitle: String {
        if isLongAgo { return "" }
        let calendar = Calendar.current
        let now = Date()

        let yearFromDate = calendar.dateComponents([.year], from: date)
        if yearFromDate.year == 1 { return "" }

        if calendar.isDateInToday(date) { return NSLocalizedString("Today", comment: "") }
        if calendar.isDateInYesterday(date) { return NSLocalizedString("Yesterday", comment: "") }

        let components = calendar.dateComponents([.year, .month, .day], from: date, to: now)
        if let year = components.year, year > 0 {
            let word = year == 1 ? NSLocalizedString("year ago", comment: "") : NSLocalizedString("years ago", comment: "")
            let fmt = DateFormatter()
            fmt.locale = Locale.current; fmt.dateFormat = "yyyy"
            return "\(fmt.string(from: date)), \(year) \(word)"
        }
        if let month = components.month, month > 0 {
            let word = month == 1 ? NSLocalizedString("month ago", comment: "") : NSLocalizedString("months ago", comment: "")
            let fmt = DateFormatter()
            fmt.locale = Locale.current; fmt.dateFormat = "MMMM"
            return "\(fmt.string(from: date)), \(month) \(word)"
        }
        if let day = components.day, day > 0 {
            if day < 7 {
                let fmt = DateFormatter()
                fmt.locale = Locale.current; fmt.dateFormat = "EEEE"
                return fmt.string(from: date)
            }
            let word = day == 1 ? NSLocalizedString("day ago", comment: "") : NSLocalizedString("days ago", comment: "")
            return "\(day) \(word)"
        }
        return NSLocalizedString("Today", comment: "")
    }

    // MARK: Bridge for ContentViewModel APIs still typed on ContactsGroup

    var asContactsGroup: ContactsGroup {
        ContactsGroup(date: date, contacts: contacts, parsedContacts: parsedContacts, isLongAgo: isLongAgo)
    }

    // MARK: Hashable / Equatable

    static func == (lhs: UnifiedFeedGroup, rhs: UnifiedFeedGroup) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - UnifiedPeopleFeedView

struct UnifiedPeopleFeedView: View {

    // MARK: Data
    let contacts: [Contact]
    let parsedContacts: [Contact]
    let notes: [Note]
    let filter: PeopleFeedFilter
    let feedRefreshTrigger: Int

    // MARK: Configuration
    let useSafeTitle: Bool
    let showInitialSyncState: Bool
    let isLowOnDeviceStorage: Bool
    let isOffline: Bool

    // MARK: Callbacks — contact selection
    let onContactSelected: (UUID) -> Void
    let onNoteSelected: (UUID, UUID) -> Void

    // MARK: Callbacks — header actions
    let onImport: (UnifiedFeedGroup) -> Void
    let onEditDate: (UnifiedFeedGroup) -> Void
    let onEditTag: (UnifiedFeedGroup) -> Void
    let onRenameTag: (UnifiedFeedGroup) -> Void
    let onDeleteAll: (UnifiedFeedGroup) -> Void
    let onChangeDateForContact: (Contact) -> Void
    let onTapHeader: (UnifiedFeedGroup) -> Void
    let onDropRecords: ([ContactDragRecord], UnifiedFeedGroup) -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        UnifiedPeopleFeedRepresentable(
            contacts: contacts,
            parsedContacts: parsedContacts,
            notes: notes,
            filter: filter,
            feedRefreshTrigger: feedRefreshTrigger,
            useSafeTitle: useSafeTitle,
            showInitialSyncState: showInitialSyncState,
            isLowOnDeviceStorage: isLowOnDeviceStorage,
            isOffline: isOffline,
            modelContext: modelContext,
            onContactSelected: onContactSelected,
            onNoteSelected: onNoteSelected,
            onImport: onImport,
            onEditDate: onEditDate,
            onEditTag: onEditTag,
            onRenameTag: onRenameTag,
            onDeleteAll: onDeleteAll,
            onChangeDateForContact: onChangeDateForContact,
            onTapHeader: onTapHeader,
            onDropRecords: onDropRecords
        )
    }

    // MARK: - Static Grouping

    /// Merges contacts and notes into date-aligned sections.
    /// Contacts appear before notes within each section (they are the "headline").
    static func computeGroups(
        contacts: [Contact],
        parsedContacts: [Contact],
        notes: [Note]
    ) -> [UnifiedFeedGroup] {
        let calendar = Calendar.current

        let longAgoContacts = contacts.filter { $0.isMetLongAgo }
        let regularContacts  = contacts.filter { !$0.isMetLongAgo }
        let longAgoParsed    = parsedContacts.filter { $0.isMetLongAgo }
        let regularParsed    = parsedContacts.filter { !$0.isMetLongAgo }
        let longAgoNotes     = notes.filter { $0.isLongAgo }
        let regularNotes     = notes.filter { !$0.isLongAgo }

        let contactsByDate = Dictionary(grouping: regularContacts) {
            calendar.startOfDay(for: $0.timestamp)
        }
        let parsedByDate = Dictionary(grouping: regularParsed) {
            calendar.startOfDay(for: $0.timestamp)
        }
        let notesByDate = Dictionary(grouping: regularNotes) {
            calendar.startOfDay(for: $0.creationDate)
        }

        let allDates = Set(contactsByDate.keys)
            .union(parsedByDate.keys)
            .union(notesByDate.keys)

        var result: [UnifiedFeedGroup] = []

        if !longAgoContacts.isEmpty || !longAgoParsed.isEmpty || !longAgoNotes.isEmpty {
            result.append(UnifiedFeedGroup(
                date: .distantPast,
                contacts: longAgoContacts.sorted { $0.timestamp < $1.timestamp },
                parsedContacts: longAgoParsed.sorted { $0.timestamp < $1.timestamp },
                notes: longAgoNotes.sorted { $0.creationDate < $1.creationDate },
                isLongAgo: true
            ))
        }

        let datedGroups = allDates.map { date in
            UnifiedFeedGroup(
                date: date,
                contacts: (contactsByDate[date] ?? []).sorted { $0.timestamp < $1.timestamp },
                parsedContacts: (parsedByDate[date] ?? []).sorted { $0.timestamp < $1.timestamp },
                notes: (notesByDate[date] ?? []).sorted { $0.creationDate < $1.creationDate },
                isLongAgo: false
            )
        }
        .sorted { $0.date < $1.date }

        result.append(contentsOf: datedGroups)
        return result
    }
}

// MARK: - UIViewControllerRepresentable

private struct UnifiedPeopleFeedRepresentable: UIViewControllerRepresentable {
    let contacts: [Contact]
    let parsedContacts: [Contact]
    let notes: [Note]
    let filter: PeopleFeedFilter
    let feedRefreshTrigger: Int
    let useSafeTitle: Bool
    let showInitialSyncState: Bool
    let isLowOnDeviceStorage: Bool
    let isOffline: Bool
    let modelContext: ModelContext

    let onContactSelected: (UUID) -> Void
    let onNoteSelected: (UUID, UUID) -> Void
    let onImport: (UnifiedFeedGroup) -> Void
    let onEditDate: (UnifiedFeedGroup) -> Void
    let onEditTag: (UnifiedFeedGroup) -> Void
    let onRenameTag: (UnifiedFeedGroup) -> Void
    let onDeleteAll: (UnifiedFeedGroup) -> Void
    let onChangeDateForContact: (Contact) -> Void
    let onTapHeader: (UnifiedFeedGroup) -> Void
    let onDropRecords: ([ContactDragRecord], UnifiedFeedGroup) -> Void

    func makeUIViewController(context: Context) -> UnifiedPeopleFeedViewController {
        let vc = UnifiedPeopleFeedViewController(modelContext: modelContext)
        assignCallbacks(to: vc)
        vc.loadViewIfNeeded()
        vc.update(
            contacts: contacts,
            parsedContacts: parsedContacts,
            notes: notes,
            filter: filter,
            useSafeTitle: useSafeTitle,
            showInitialSyncState: showInitialSyncState,
            isLowOnDeviceStorage: isLowOnDeviceStorage,
            isOffline: isOffline
        )
        return vc
    }

    func updateUIViewController(_ vc: UnifiedPeopleFeedViewController, context: Context) {
        assignCallbacks(to: vc)
        vc.update(
            contacts: contacts,
            parsedContacts: parsedContacts,
            notes: notes,
            filter: filter,
            useSafeTitle: useSafeTitle,
            showInitialSyncState: showInitialSyncState,
            isLowOnDeviceStorage: isLowOnDeviceStorage,
            isOffline: isOffline
        )
    }

    private func assignCallbacks(to vc: UnifiedPeopleFeedViewController) {
        vc.onContactSelected = onContactSelected
        vc.onNoteSelected    = onNoteSelected
        vc.onImport          = onImport
        vc.onEditDate        = onEditDate
        vc.onEditTag         = onEditTag
        vc.onRenameTag       = onRenameTag
        vc.onDeleteAll       = onDeleteAll
        vc.onChangeDateForContact = onChangeDateForContact
        vc.onTapHeader       = onTapHeader
        vc.onDropRecords     = onDropRecords
    }
}
