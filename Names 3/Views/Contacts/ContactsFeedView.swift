//
//  ContactsFeedView.swift
//  Names 3
//
//  SwiftUI wrapper for the UIKit contacts feed. Uses ContactsFeedViewController
//  with UICollectionView, compositional layout, and diffable data source.
//

import SwiftUI
import SwiftData
import TipKit

// MARK: - ContactsFeedView (SwiftUI wrapper)

struct ContactsFeedView: View {
    let contacts: [Contact]
    let parsedContacts: [Contact]
    let configuration: ContactsFeedConfiguration
    let callbacks: ContactsFeedCallbacks

    @Environment(\.modelContext) private var modelContext

    init(
        contacts: [Contact],
        parsedContacts: [Contact],
        useSafeTitle: Bool,
        showInitialSyncState: Bool,
        isLowOnDeviceStorage: Bool,
        isOffline: Bool,
        onContactSelected: @escaping (UUID) -> Void,
        onImport: @escaping (ContactsGroup) -> Void,
        onEditDate: @escaping (ContactsGroup) -> Void,
        onEditTag: @escaping (ContactsGroup) -> Void,
        onRenameTag: @escaping (ContactsGroup) -> Void,
        onDeleteAll: @escaping (ContactsGroup) -> Void,
        onChangeDateForContact: @escaping (Contact) -> Void,
        onTapHeader: @escaping (ContactsGroup) -> Void,
        onDropRecords: @escaping ([ContactDragRecord], ContactsGroup) -> Void
    ) {
        self.contacts = contacts
        self.parsedContacts = parsedContacts
        self.configuration = ContactsFeedConfiguration(
            useSafeTitle: useSafeTitle,
            showInitialSyncState: showInitialSyncState,
            isLowOnDeviceStorage: isLowOnDeviceStorage,
            isOffline: isOffline
        )
        self.callbacks = ContactsFeedCallbacks(
            onContactSelected: onContactSelected,
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

    var body: some View {
        ContactsFeedViewControllerRepresentable(
            contacts: contacts,
            parsedContacts: parsedContacts,
            configuration: configuration,
            callbacks: callbacks,
            modelContext: modelContext
        )
    }

    // MARK: - Supporting Types

    struct ContactsFeedConfiguration {
        let useSafeTitle: Bool
        let showInitialSyncState: Bool
        let isLowOnDeviceStorage: Bool
        let isOffline: Bool
    }

    struct ContactsFeedCallbacks {
        let onContactSelected: (UUID) -> Void
        let onImport: (ContactsGroup) -> Void
        let onEditDate: (ContactsGroup) -> Void
        let onEditTag: (ContactsGroup) -> Void
        let onRenameTag: (ContactsGroup) -> Void
        let onDeleteAll: (ContactsGroup) -> Void
        let onChangeDateForContact: (Contact) -> Void
        let onTapHeader: (ContactsGroup) -> Void
        let onDropRecords: ([ContactDragRecord], ContactsGroup) -> Void
    }

    // MARK: - Static Helpers

    static func computeGroups(contacts: [Contact], parsedContacts: [Contact]) -> [ContactsGroup] {
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

        var result: [ContactsGroup] = []

        if !longAgoContacts.isEmpty || !longAgoParsed.isEmpty {
            let longAgoGroup = ContactsGroup(
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
            return ContactsGroup(
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
}

// MARK: - UIViewControllerRepresentable

private struct ContactsFeedViewControllerRepresentable: UIViewControllerRepresentable {
    let contacts: [Contact]
    let parsedContacts: [Contact]
    let configuration: ContactsFeedView.ContactsFeedConfiguration
    let callbacks: ContactsFeedView.ContactsFeedCallbacks
    let modelContext: ModelContext

    func makeUIViewController(context: Context) -> ContactsFeedViewController {
        let vc = ContactsFeedViewController(
            modelContext: modelContext,
            useSafeTitle: configuration.useSafeTitle,
            showInitialSyncState: configuration.showInitialSyncState,
            isLowOnDeviceStorage: configuration.isLowOnDeviceStorage,
            isOffline: configuration.isOffline
        )
        vc.onContactSelected = callbacks.onContactSelected
        vc.onImport = callbacks.onImport
        vc.onEditDate = callbacks.onEditDate
        vc.onEditTag = callbacks.onEditTag
        vc.onRenameTag = callbacks.onRenameTag
        vc.onDeleteAll = callbacks.onDeleteAll
        vc.onChangeDateForContact = callbacks.onChangeDateForContact
        vc.onTapHeader = callbacks.onTapHeader
        vc.onDropRecords = callbacks.onDropRecords
        // Ensure view hierarchy is ready before applying snapshot (standard UIViewControllerRepresentable pattern)
        vc.loadViewIfNeeded()
        vc.update(
            contacts: contacts,
            parsedContacts: parsedContacts,
            useSafeTitle: configuration.useSafeTitle,
            showInitialSyncState: configuration.showInitialSyncState,
            isLowOnDeviceStorage: configuration.isLowOnDeviceStorage,
            isOffline: configuration.isOffline
        )
        return vc
    }

    func updateUIViewController(_ vc: ContactsFeedViewController, context: Context) {
        vc.onContactSelected = callbacks.onContactSelected
        vc.onImport = callbacks.onImport
        vc.onEditDate = callbacks.onEditDate
        vc.onEditTag = callbacks.onEditTag
        vc.onRenameTag = callbacks.onRenameTag
        vc.onDeleteAll = callbacks.onDeleteAll
        vc.onChangeDateForContact = callbacks.onChangeDateForContact
        vc.onTapHeader = callbacks.onTapHeader
        vc.onDropRecords = callbacks.onDropRecords
        vc.update(
            contacts: contacts,
            parsedContacts: parsedContacts,
            useSafeTitle: configuration.useSafeTitle,
            showInitialSyncState: configuration.showInitialSyncState,
            isLowOnDeviceStorage: configuration.isLowOnDeviceStorage,
            isOffline: configuration.isOffline
        )
    }
}

// MARK: - ContactsFeedEmptyStateView (SwiftUI - kept for any standalone use)

struct ContactsFeedEmptyStateViewSwiftUI: View {
    let showSyncing: Bool
    let showNoStorage: Bool
    let isOffline: Bool

    var body: some View {
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
}
