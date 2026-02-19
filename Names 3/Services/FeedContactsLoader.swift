//
//  FeedContactsLoader.swift
//  Names 3
//
//  Loads contacts on a background thread to keep main thread free during launch.
//  SwiftData @Query blocks 100s+ when CloudKit syncs; this moves the heavy fetch off main.
//

import Foundation
import SwiftData

enum FeedContactsLoader {

    /// Fetches contact UUIDs on background thread (unblocks main), then refetches on main for display.
    static func loadContacts(
        container: ModelContainer,
        mainContext: ModelContext,
        fetchLimit: Int = 500
    ) async -> [Contact] {
        let ids = await Task.detached(priority: .userInitiated) { () -> [UUID] in
            let ctx = ModelContext(container)
            var descriptor = FetchDescriptor<Contact>(
                predicate: #Predicate<Contact> { !$0.isArchived },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = fetchLimit
            let contacts = (try? ctx.fetch(descriptor)) ?? []
            return contacts.map(\.uuid)
        }.value

        guard !ids.isEmpty else { return [] }

        return await MainActor.run {
            let descriptor = FetchDescriptor<Contact>(
                predicate: #Predicate<Contact> { ids.contains($0.uuid) },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            return (try? mainContext.fetch(descriptor)) ?? []
        }
    }
}
