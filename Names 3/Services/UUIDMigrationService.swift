//
//  UUIDMigrationService.swift
//  Names 3
//
//  One-time migration: ensure Contact, Note, Tag, QuickNote have unique non-zero UUIDs.
//  Runs on the provided ModelContext's thread (main or background). Use from background to avoid blocking launch.
//

import Foundation
import SwiftData
import os

enum UUIDMigrationService {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "UUIDMigration")
    private static let zeroUUIDString = "00000000-0000-0000-0000-000000000000"
    static let defaultsKey = "Names3.didFixUUIDs.v1"

    /// Returns true if the store has no data that could need UUID migration (no contacts).
    /// Used to skip running the full migration on empty stores (e.g. after CloudKit reset or fresh install).
    static func isStoreEmpty(context: ModelContext) -> Bool {
        do {
            var descriptor = FetchDescriptor<Contact>()
            descriptor.fetchLimit = 1
            let contacts = try context.fetch(descriptor)
            return contacts.isEmpty
        } catch {
            logger.error("❌ Failed to check store empty: \(error, privacy: .public)")
            return false
        }
    }

    /// Runs the migration using the given context. Call from the same thread/actor that owns the context.
    /// Returns true if any changes were made and saved.
    static func runMigration(context: ModelContext) -> Bool {
        var anyFixed = false

        do {
            let all = try context.fetch(FetchDescriptor<Contact>())
            var seen = Set<UUID>()
            var fixed = 0
            for c in all {
                var u = c.uuid
                if u.uuidString == zeroUUIDString || seen.contains(u) {
                    var newU = UUID()
                    while seen.contains(newU) { newU = UUID() }
                    c.uuid = newU
                    u = newU
                    fixed += 1
                }
                seen.insert(u)
            }
            if fixed > 0 {
                try context.save()
                anyFixed = true
                logger.info("🔧 Fixed \(fixed) duplicate/zero UUIDs in Contact")
            }
        } catch {
            logger.error("❌ Failed UUID fix for Contact: \(error, privacy: .public)")
        }

        do {
            let all = try context.fetch(FetchDescriptor<Note>())
            var seen = Set<UUID>()
            var fixed = 0
            for n in all {
                var u = n.uuid
                if u.uuidString == zeroUUIDString || seen.contains(u) {
                    var newU = UUID()
                    while seen.contains(newU) { newU = UUID() }
                    n.uuid = newU
                    u = newU
                    fixed += 1
                }
                seen.insert(u)
            }
            if fixed > 0 {
                try context.save()
                anyFixed = true
                logger.info("🔧 Fixed \(fixed) duplicate/zero UUIDs in Note")
            }
        } catch {
            logger.error("❌ Failed UUID fix for Note: \(error, privacy: .public)")
        }

        do {
            let all = try context.fetch(FetchDescriptor<Tag>())
            var seen = Set<UUID>()
            var fixed = 0
            for t in all {
                var u = t.uuid
                if u.uuidString == zeroUUIDString || seen.contains(u) {
                    var newU = UUID()
                    while seen.contains(newU) { newU = UUID() }
                    t.uuid = newU
                    u = newU
                    fixed += 1
                }
                seen.insert(u)
            }
            if fixed > 0 {
                try context.save()
                anyFixed = true
                logger.info("🔧 Fixed \(fixed) duplicate/zero UUIDs in Tag")
            }
        } catch {
            logger.error("❌ Failed UUID fix for Tag: \(error, privacy: .public)")
        }

        do {
            let all = try context.fetch(FetchDescriptor<QuickNote>())
            var seen = Set<UUID>()
            var fixed = 0
            for q in all {
                var u = q.uuid
                if u.uuidString == zeroUUIDString || seen.contains(u) {
                    var newU = UUID()
                    while seen.contains(newU) { newU = UUID() }
                    q.uuid = newU
                    u = newU
                    fixed += 1
                }
                seen.insert(u)
            }
            if fixed > 0 {
                try context.save()
                anyFixed = true
                logger.info("🔧 Fixed \(fixed) duplicate/zero UUIDs in QuickNote")
            }
        } catch {
            logger.error("❌ Failed UUID fix for QuickNote: \(error, privacy: .public)")
        }

        return anyFixed
    }
}
