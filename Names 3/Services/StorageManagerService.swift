//
//  StorageManagerService.swift
//  Names 3
//
//  Provides app and device storage metrics for the Storage Manager UI.
//

import Foundation
import SwiftData
import UIKit
import os

extension Notification.Name {
    static let storageDidChange = Notification.Name("Names3.StorageDidChange")
}

/// Per-category breakdown of "other" database storage (bytes).
struct OtherDataBreakdown: Sendable {
    var contactMetadata: Int64 = 0      // Contact names, summaries, groups (excluding photo)
    var faceMetadata: Int64 = 0         // FaceEmbedding asset IDs, bounding boxes (excluding thumb/embedding)
    var faceClusters: Int64 = 0        // FaceCluster centroidEmbedding + metadata
    var quizHistory: Int64 = 0         // QuizPerformance
    var noteRehearsal: Int64 = 0       // NoteRehearsalPerformance
    var quizSessions: Int64 = 0       // QuizSession
    var deletedPhotos: Int64 = 0      // DeletedPhoto asset IDs
    var databaseOverhead: Int64 = 0   // WAL, indexes, fragmentation

    var attributedTotal: Int64 {
        contactMetadata + faceMetadata + faceClusters + quizHistory + noteRehearsal + quizSessions + deletedPhotos
    }
}

/// Storage breakdown for the app. All sizes in bytes.
struct StorageBreakdown: Sendable {
    var appTotal: Int64 = 0
    var databaseStore: Int64 = 0
    var databaseWAL: Int64 = 0
    var databaseSHM: Int64 = 0
    var batchStore: Int64 = 0
    var caches: Int64 = 0
    var documents: Int64 = 0
    var deviceFree: Int64 = 0
    var deviceTotal: Int64 = 0
    var isLowOnDevice: Bool = false
    
    /// People: contact photos (Contact.photo)
    var peoplePhotos: Int64 = 0
    /// Faces: face thumbnails (FaceEmbedding.thumbnailData)
    var faceThumbnails: Int64 = 0
    /// Faces: embedding vectors (FaceEmbedding.embeddingData)
    var faceEmbeddings: Int64 = 0
    /// Number of face embeddings
    var faceCount: Int = 0
    
    /// Notes (Note.content)
    var notesSize: Int64 = 0
    /// Quick notes (QuickNote.content)
    var quickNotesSize: Int64 = 0
    /// Tags (Tag.name)
    var tagsSize: Int64 = 0
    /// Remainder: metadata, quiz, overhead
    var otherMetadataSize: Int64 = 0

    /// Breakdown of otherMetadataSize into attributable categories
    var otherBreakdown: OtherDataBreakdown = OtherDataBreakdown()

    var appTotalFormatted: String { formatBytes(appTotal) }
    var deviceFreeFormatted: String { formatBytes(deviceFree) }
    var deviceTotalFormatted: String { formatBytes(deviceTotal) }
    
    var peopleTotal: Int64 { peoplePhotos }
    var facesTotal: Int64 { faceThumbnails + faceEmbeddings }
    var otherDataTotal: Int64 { notesSize + quickNotesSize + tagsSize + otherMetadataSize }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private enum StorageSizeCalculator {
    static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }
        
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  values.isDirectory != true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }
    
    static func fileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return 0 }
        return Int64(size)
    }
}

@MainActor
final class StorageManagerService {
    static let shared = StorageManagerService()
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Names3", category: "StorageManager")
    
    private init() {}
    
    /// Compute storage breakdown. Runs on background; call from Task.
    func computeBreakdown(modelContext: ModelContext? = nil) async -> StorageBreakdown {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        
        var breakdown = await Task.detached(priority: .userInitiated) {
            var b = StorageBreakdown()
            if let url = appSupport {
                b.appTotal += StorageSizeCalculator.directorySize(at: url)
                b.databaseStore += StorageSizeCalculator.fileSize(at: url.appendingPathComponent("default.store"))
                b.databaseWAL += StorageSizeCalculator.fileSize(at: url.appendingPathComponent("default.store-wal"))
                b.databaseSHM += StorageSizeCalculator.fileSize(at: url.appendingPathComponent("default.store-shm"))
                b.batchStore += StorageSizeCalculator.fileSize(at: url.appendingPathComponent("batches.store"))
                b.batchStore += StorageSizeCalculator.fileSize(at: url.appendingPathComponent("batches.store-wal"))
                b.batchStore += StorageSizeCalculator.fileSize(at: url.appendingPathComponent("batches.store-shm"))
                b.batchStore += StorageSizeCalculator.fileSize(at: url.appendingPathComponent("batches-local.store"))
                b.batchStore += StorageSizeCalculator.fileSize(at: url.appendingPathComponent("batches-local.store-wal"))
                b.batchStore += StorageSizeCalculator.fileSize(at: url.appendingPathComponent("batches-local.store-shm"))
            }
            if let url = cachesURL {
                let size = StorageSizeCalculator.directorySize(at: url)
                b.caches += size
                b.appTotal += size
            }
            if let url = documentsURL {
                let size = StorageSizeCalculator.directorySize(at: url)
                b.documents += size
                b.appTotal += size
            }
            return b
        }.value
        
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let values = try url.resourceValues(forKeys: [
                    .volumeAvailableCapacityForImportantUsageKey,
                    .volumeTotalCapacityKey
                ])
                breakdown.deviceFree = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
                breakdown.deviceTotal = Int64(values.volumeTotalCapacity ?? 0)
                breakdown.isLowOnDevice = breakdown.deviceFree < 100 * 1024 * 1024
            } catch {
                Self.logger.warning("Could not read volume capacity: \(error.localizedDescription)")
            }
        }
        
        if let ctx = modelContext {
            breakdown.peoplePhotos = computePeoplePhotosSize(context: ctx)
            let (thumb, embed, count) = computeFacesSize(context: ctx)
            breakdown.faceThumbnails = thumb
            breakdown.faceEmbeddings = embed
            breakdown.faceCount = count
            breakdown.notesSize = computeNotesSize(context: ctx)
            breakdown.quickNotesSize = computeQuickNotesSize(context: ctx)
            breakdown.tagsSize = computeTagsSize(context: ctx)
            var otherBreakdown = computeOtherBreakdown(context: ctx)
            let dbTotal = breakdown.databaseStore + breakdown.databaseWAL + breakdown.databaseSHM
            let attributed = breakdown.peopleTotal + breakdown.facesTotal + breakdown.notesSize + breakdown.quickNotesSize + breakdown.tagsSize
            breakdown.otherMetadataSize = max(0, dbTotal - attributed)
            otherBreakdown.databaseOverhead = max(0, breakdown.otherMetadataSize - otherBreakdown.attributedTotal)
            breakdown.otherBreakdown = otherBreakdown
        }
        
        return breakdown
    }
    
    /// Run storage shrink migration to downscale oversized photos. Returns (contactsShrunk, embeddingsShrunk).
    func runStorageShrink(modelContext: ModelContext) -> (Int, Int) {
        UserDefaults.standard.removeObject(forKey: StorageShrinkMigrationService.defaultsKey)
        return StorageShrinkMigrationService.runMigration(context: modelContext)
    }

    /// Compact database (checkpoint + vacuum). Returns bytes freed or nil on failure.
    func compactDatabase(modelContext: ModelContext) -> Int64? {
        DatabaseCompactor.compact(modelContext: modelContext)
    }

    /// Clear all quiz performance data. Resets spaced repetition for all contacts.
    func clearQuizHistory(context: ModelContext) -> Int {
        do {
            let all = try context.fetch(FetchDescriptor<QuizPerformance>())
            for qp in all { context.delete(qp) }
            try context.save()
            return all.count
        } catch {
            Self.logger.warning("Could not clear quiz history: \(error.localizedDescription)")
            return 0
        }
    }

    /// Clear all note rehearsal performance data.
    func clearNoteRehearsalHistory(context: ModelContext) -> Int {
        do {
            let all = try context.fetch(FetchDescriptor<NoteRehearsalPerformance>())
            for nrp in all { context.delete(nrp) }
            try context.save()
            return all.count
        } catch {
            Self.logger.warning("Could not clear note rehearsal: \(error.localizedDescription)")
            return 0
        }
    }

    /// Clear in-memory image cache (frees RAM, not disk).
    func clearImageCache() {
        ImageCacheService.shared.clearCache()
    }
    
    private func computePeoplePhotosSize(context: ModelContext) -> Int64 {
        do {
            let contacts = try context.fetch(FetchDescriptor<Contact>())
            return contacts.reduce(0) { $0 + Int64($1.photo.count) }
        } catch {
            Self.logger.warning("Could not fetch contacts for storage: \(error.localizedDescription)")
            return 0
        }
    }
    
    private func computeFacesSize(context: ModelContext) -> (thumbnails: Int64, embeddings: Int64, count: Int) {
        do {
            let embeddings = try context.fetch(FetchDescriptor<FaceEmbedding>())
            let thumb = embeddings.reduce(0) { $0 + Int64($1.thumbnailData.count) }
            let embed = embeddings.reduce(0) { $0 + Int64($1.embeddingData.count) }
            return (thumb, embed, embeddings.count)
        } catch {
            Self.logger.warning("Could not fetch face embeddings for storage: \(error.localizedDescription)")
            return (0, 0, 0)
        }
    }
    
    private func computeNotesSize(context: ModelContext) -> Int64 {
        do {
            let notes = try context.fetch(FetchDescriptor<Note>())
            return notes.reduce(0) { $0 + Int64($1.content.utf8.count) }
        } catch {
            Self.logger.warning("Could not fetch notes for storage: \(error.localizedDescription)")
            return 0
        }
    }
    
    private func computeQuickNotesSize(context: ModelContext) -> Int64 {
        do {
            let quickNotes = try context.fetch(FetchDescriptor<QuickNote>())
            return quickNotes.reduce(0) { $0 + Int64($1.content.utf8.count) }
        } catch {
            Self.logger.warning("Could not fetch quick notes for storage: \(error.localizedDescription)")
            return 0
        }
    }
    
    private func computeTagsSize(context: ModelContext) -> Int64 {
        do {
            let tags = try context.fetch(FetchDescriptor<Tag>())
            return tags.reduce(0) { $0 + Int64($1.name.utf8.count) }
        } catch {
            Self.logger.warning("Could not fetch tags for storage: \(error.localizedDescription)")
            return 0
        }
    }

    private func computeOtherBreakdown(context: ModelContext) -> OtherDataBreakdown {
        var b = OtherDataBreakdown()
        do {
            let contacts = try context.fetch(FetchDescriptor<Contact>())
            b.contactMetadata = contacts.reduce(0) { acc, c in
                acc + Int64((c.name ?? "").utf8.count)
                    + Int64((c.nicknames ?? []).joined().utf8.count)
                    + Int64((c.summary ?? "").utf8.count)
                    + Int64(c.group.utf8.count)
            }
        } catch {
            Self.logger.warning("Could not fetch contacts for other breakdown: \(error.localizedDescription)")
        }
        do {
            let embeddings = try context.fetch(FetchDescriptor<FaceEmbedding>())
            b.faceMetadata = embeddings.reduce(0) { acc, e in
                acc + Int64(e.assetIdentifier.utf8.count)
                    + Int64(e.boundingBox.count * MemoryLayout<Float>.size)
            }
        } catch {
            Self.logger.warning("Could not fetch face embeddings for other breakdown: \(error.localizedDescription)")
        }
        do {
            let clusters = try context.fetch(FetchDescriptor<FaceCluster>())
            b.faceClusters = clusters.reduce(0) { acc, c in
                acc + Int64(c.centroidEmbedding.count) + 64
            }
        } catch {
            Self.logger.warning("Could not fetch face clusters for other breakdown: \(error.localizedDescription)")
        }
        do {
            let quiz = try context.fetch(FetchDescriptor<QuizPerformance>())
            b.quizHistory = Int64(quiz.count) * 80
        } catch {
            Self.logger.warning("Could not fetch quiz performance for other breakdown: \(error.localizedDescription)")
        }
        do {
            let rehearsal = try context.fetch(FetchDescriptor<NoteRehearsalPerformance>())
            b.noteRehearsal = Int64(rehearsal.count) * 64
        } catch {
            Self.logger.warning("Could not fetch note rehearsal for other breakdown: \(error.localizedDescription)")
        }
        do {
            let sessions = try context.fetch(FetchDescriptor<QuizSession>())
            b.quizSessions = sessions.reduce(0) { acc, s in
                acc + Int64(s.contactIDs.count * 16) + 64
            }
        } catch {
            Self.logger.warning("Could not fetch quiz sessions for other breakdown: \(error.localizedDescription)")
        }
        do {
            let deleted = try context.fetch(FetchDescriptor<DeletedPhoto>())
            b.deletedPhotos = deleted.reduce(0) { acc, d in
                acc + Int64(d.assetLocalIdentifier.utf8.count) + 16
            }
        } catch {
            Self.logger.warning("Could not fetch deleted photos for other breakdown: \(error.localizedDescription)")
        }
        return b
    }
    
    // MARK: - Item-level fetch (for identify & delete UI)
    
    /// Contacts with photo size > 0, sorted by size descending.
    func fetchContactsWithPhotoSizes(context: ModelContext) -> [(Contact, Int64)] {
        do {
            let contacts = try context.fetch(FetchDescriptor<Contact>())
            return contacts
                .filter { !$0.photo.isEmpty }
                .map { ($0, Int64($0.photo.count)) }
                .sorted { $0.1 > $1.1 }
        } catch {
            Self.logger.warning("Could not fetch contacts: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Unassigned faces (contactUUID == nil) and faces grouped by contact.
    func fetchFacesBreakdown(context: ModelContext) -> (
        unassignedCount: Int,
        unassignedSize: Int64,
        byContact: [(name: String, uuid: UUID, count: Int, size: Int64)]
    ) {
        do {
            let embeddings = try context.fetch(FetchDescriptor<FaceEmbedding>())
            let unassigned = embeddings.filter { $0.contactUUID == nil }
            let unassignedSize = unassigned.reduce(0) { $0 + Int64($1.thumbnailData.count + $1.embeddingData.count) }
            let byUUID = Dictionary(grouping: embeddings.filter { $0.contactUUID != nil }) { $0.contactUUID! }
            let contacts = try context.fetch(FetchDescriptor<Contact>())
            let contactMap = Dictionary(uniqueKeysWithValues: contacts.map { ($0.uuid, $0) })
            var byContact: [(name: String, uuid: UUID, count: Int, size: Int64)] = []
            for (uuid, embs) in byUUID {
                let size = embs.reduce(0) { $0 + Int64($1.thumbnailData.count + $1.embeddingData.count) }
                let name = contactMap[uuid]?.name ?? ""
                byContact.append((name: name, uuid: uuid, count: embs.count, size: size))
            }
            byContact.sort { $0.size > $1.size }
            return (unassigned.count, unassignedSize, byContact)
        } catch {
            Self.logger.warning("Could not fetch face breakdown: \(error.localizedDescription)")
            return (0, 0, [])
        }
    }
    
    func fetchNotesWithSizes(context: ModelContext) -> [(Note, Int64)] {
        do {
            let notes = try context.fetch(FetchDescriptor<Note>())
            return notes
                .map { ($0, Int64($0.content.utf8.count)) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
        } catch {
            Self.logger.warning("Could not fetch notes: \(error.localizedDescription)")
            return []
        }
    }
    
    func fetchQuickNotesWithSizes(context: ModelContext) -> [(QuickNote, Int64)] {
        do {
            let notes = try context.fetch(FetchDescriptor<QuickNote>())
            return notes
                .map { ($0, Int64($0.content.utf8.count)) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
        } catch {
            Self.logger.warning("Could not fetch quick notes: \(error.localizedDescription)")
            return []
        }
    }
    
    func fetchTagsWithSizes(context: ModelContext) -> [(Tag, Int64)] {
        do {
            let tags = try context.fetch(FetchDescriptor<Tag>())
            var seen = Set<UUID>()
            return tags
                .compactMap { tag -> (Tag, Int64)? in
                    let size = Int64(tag.name.utf8.count)
                    guard size > 0, seen.insert(tag.uuid).inserted else { return nil }
                    return (tag, size)
                }
                .sorted { $0.1 > $1.1 }
        } catch {
            Self.logger.warning("Could not fetch tags: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Delete actions
    
    func clearContactPhoto(_ contact: Contact) {
        contact.photo = Data()
        contact.hasPhotoGradient = false
    }
    
    func deleteContact(_ contact: Contact, context: ModelContext) {
        deleteFacesForContact(uuid: contact.uuid, context: context)
        for note in contact.notes ?? [] { context.delete(note) }
        if let qp = contact.quizPerformance { context.delete(qp) }
        if let nrp = contact.noteRehearsalPerformance { context.delete(nrp) }
        context.delete(contact)
        try? context.save()
    }
    
    func deleteUnassignedFaces(context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<FaceEmbedding>(
                predicate: #Predicate<FaceEmbedding> { $0.contactUUID == nil }
            )
            let embeddings = try context.fetch(descriptor)
            for e in embeddings { context.delete(e) }
            try context.save()
        } catch {
            Self.logger.warning("Could not delete unassigned faces: \(error.localizedDescription)")
        }
    }
    
    func deleteFacesForContact(uuid: UUID, context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<FaceEmbedding>(
                predicate: #Predicate<FaceEmbedding> { $0.contactUUID == uuid }
            )
            let embeddings = try context.fetch(descriptor)
            for e in embeddings { context.delete(e) }
            try context.save()
        } catch {
            Self.logger.warning("Could not delete faces for contact: \(error.localizedDescription)")
        }
    }
    
    func deleteNote(_ note: Note, context: ModelContext) {
        context.delete(note)
        try? context.save()
    }
    
    func deleteQuickNote(_ note: QuickNote, context: ModelContext) {
        context.delete(note)
        try? context.save()
    }
    
    func deleteTag(_ tag: Tag, context: ModelContext) {
        context.delete(tag)
        try? context.save()
    }
}
