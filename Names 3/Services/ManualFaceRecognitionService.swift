//
//  ManualFaceRecognitionService.swift
//  Names 3
//
//  Find Similar Faces: runs only when the user explicitly triggers it (e.g. "Find Similar Faces" button).
//  No background tasks, no automatic scanning.
//

import Foundation
import SwiftData
import Photos
import UIKit
import ImageIO

/// Sendable box for passing non-Sendable references into @Sendable closures.
private final class SendableRef<T>: @unchecked Sendable {
    nonisolated(unsafe) let value: T
    init(_ value: T) { self.value = value }
}

/// Sendable result of a face match (for passing from background to MainActor).
private struct FaceMatchResult: Sendable {
    let assetIdentifier: String
    let embeddingData: Data
    let boundingBox: [Float]
    let qualityScore: Float
    let photoDate: Date
    let thumbnailData: Data
    let yaw: Float
    let pitch: Float
    let roll: Float
}

/// Runs "Find Similar Faces" for a contact only when the user triggers it. No automatic or background analysis.
final class ManualFaceRecognitionService {

    static let shared = ManualFaceRecognitionService()

    private let faceRecognitionService = FaceRecognitionService.shared
    private let batchSize = 50
    private let initialBatchLimit = 2_000
    private let similarityThreshold: Float = 0.88
    private let observationDistanceThreshold: Float = 0.55

    private let processingLock = NSLock()
    private var _processingContactUUIDs: Set<UUID> = []

    private func addProcessing(contactUUID: UUID) -> Bool {
        processingLock.lock()
        defer { processingLock.unlock() }
        if _processingContactUUIDs.contains(contactUUID) { return false }
        _processingContactUUIDs.insert(contactUUID)
        return true
    }

    private func removeProcessing(contactUUID: UUID) {
        processingLock.lock()
        defer { processingLock.unlock() }
        _processingContactUUIDs.remove(contactUUID)
    }

    /// Run Find Similar Faces for one contact. Called only when user taps "Find Similar Faces".
    @MainActor
    func findSimilarFaces(
        for contact: Contact,
        in modelContext: ModelContext,
        appContainer: ModelContainer? = nil,
        progressHandler: @escaping (Int, Int) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        print("[FaceRecognition] findSimilarFaces started contact=\(contact.displayName)")
        let contactUUID = contact.uuid
        guard addProcessing(contactUUID: contactUUID) else {
            print("[FaceRecognition] ❌ This contact already being analyzed, rejecting")
            completion(.failure(NSError(domain: "ManualFaceRecognition", code: -1,
                                       userInfo: [NSLocalizedDescriptionKey: "Analysis already in progress for this person"])))
            return
        }

        let contactPhotoAssetId = "contact-\(contact.uuid.uuidString)"
        var alreadyProcessedAssetIds: Set<String> = []
        do {
            let searchUUID: UUID? = contact.uuid
            let descriptor = FetchDescriptor<FaceEmbedding>(
                predicate: #Predicate<FaceEmbedding> { embed in embed.contactUUID == searchUUID }
            )
            let existing = try modelContext.fetch(descriptor)
            alreadyProcessedAssetIds = Set(existing.map(\.assetIdentifier).filter { $0 != contactPhotoAssetId })
        } catch {
            print("[FaceRecognition] Could not fetch existing embeddings for skip list: \(error)")
        }
        if !alreadyProcessedAssetIds.isEmpty {
            print("[FaceRecognition] Skipping \(alreadyProcessedAssetIds.count) already-processed photo(s) for this contact")
        }

        var assetIdsWithStoredFaces: Set<String> = []
        do {
            assetIdsWithStoredFaces = try FaceAnalysisCache.fetchAssetIdentifiersWithStoredFaces(in: modelContext)
        } catch {
            print("[FaceRecognition] Could not fetch global stored-faces set: \(error)")
        }

        if let container = appContainer {
            runAnalysisOffMain(
                contactUUID: contactUUID,
                container: container,
                alreadyProcessedAssetIds: alreadyProcessedAssetIds,
                progressHandler: progressHandler,
                completion: completion
            )
            return
        }

        // Fallback: create a separate container (different store). Results will NOT sync.
        // Callers should pass appContainer (e.g. modelContext.container) so we write to the main store.
        print("[FaceRecognition] ⚠️ appContainer is nil; using fallback container — results will not sync to iCloud")

        Task { @MainActor in
            guard !Task.isCancelled else { return }
            guard let container = try? ModelContainer(
                for: Contact.self, FaceEmbedding.self, FaceCluster.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            ) else {
                completion(.failure(NSError(domain: "ManualFaceRecognition", code: -6, userInfo: [NSLocalizedDescriptionKey: "Could not create model container"])))
                removeProcessing(contactUUID: contactUUID)
                return
            }
            let workContext = ModelContext(container)
            do {
                let descriptor = FetchDescriptor<Contact>(
                    predicate: #Predicate<Contact> { c in c.uuid == contactUUID }
                )
                let contacts = try workContext.fetch(descriptor)
                guard let contactInBg = contacts.first else {
                    throw NSError(domain: "ManualFaceRecognition", code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "Contact not found in context"])
                }

                print("[FaceRecognition] Getting reference embeddings for \(contactInBg.displayName)...")
                let referenceEmbeddings = try await getReferenceEmbeddings(for: contactInBg, in: workContext)
                print("[FaceRecognition] Using \(referenceEmbeddings.count) reference embedding(s)")

                let contactPhotoDate = Self.photoCaptureDate(from: contactInBg.photo) ?? contactInBg.timestamp
                let anchorDates = [contactPhotoDate] + referenceEmbeddings.map(\.photoDate)
                let allAssets = await fetchPhotoAssetsSortedByProximity(toAnchorDates: anchorDates)
                let assets = allAssets.filter { !alreadyProcessedAssetIds.contains($0.localIdentifier) }
                let toProcess = assets.filter { !assetIdsWithStoredFaces.contains($0.localIdentifier) }
                let toMatchOnly = assets.filter { assetIdsWithStoredFaces.contains($0.localIdentifier) }
                print("[FaceRecognition] Fetched \(allAssets.count) photo assets; \(assets.count) not yet processed for contact; \(toProcess.count) to run Vision, \(toMatchOnly.count) match-only")

                var foundFacesCount = 0
                var processedCount = 0
                let totalToProcess = min(toProcess.count, initialBatchLimit)
                let stoppedEarly = toProcess.count > initialBatchLimit

                for batchStart in stride(from: 0, to: totalToProcess, by: batchSize) {
                    guard !Task.isCancelled else { break }
                    let batchEnd = min(batchStart + batchSize, totalToProcess)
                    let batch = Array(toProcess[batchStart..<batchEnd])
                    let matchCount = await processPhotoBatch(
                        batch,
                        referenceEmbeddings: referenceEmbeddings,
                        contactUUID: contactUUID,
                        modelContext: workContext
                    )
                    foundFacesCount += matchCount
                    processedCount += batch.count
                    progressHandler(processedCount, totalToProcess)
                }

                let matchOnlyCount = await matchStoredEmbeddingsOnly(
                    assets: toMatchOnly,
                    referenceEmbeddings: referenceEmbeddings,
                    contactUUID: contactUUID,
                    modelContext: workContext
                )
                foundFacesCount += matchOnlyCount

                print("[FaceRecognition] findSimilarFaces done: found \(foundFacesCount) matching faces (\(matchOnlyCount) from stored)")
                completion(.success(foundFacesCount))
                removeProcessing(contactUUID: contactUUID)

                if stoppedEarly, processedCount < toProcess.count {
                    for batchStart in stride(from: totalToProcess, to: toProcess.count, by: batchSize) {
                        guard !Task.isCancelled else { break }
                        let batchEnd = min(batchStart + batchSize, toProcess.count)
                        let batch = Array(toProcess[batchStart..<batchEnd])
                        _ = await processPhotoBatch(
                            batch,
                            referenceEmbeddings: referenceEmbeddings,
                            contactUUID: contactUUID,
                            modelContext: workContext
                        )
                    }
                }
            } catch {
                print("[FaceRecognition] ❌ findSimilarFaces failed: \(error.localizedDescription)")
                completion(.failure(error))
                removeProcessing(contactUUID: contactUUID)
            }
        }
    }

    private nonisolated func runAnalysisOffMain(
        contactUUID: UUID,
        container: ModelContainer,
        alreadyProcessedAssetIds: Set<String>,
        progressHandler: @escaping (Int, Int) -> Void,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            let ctx = ModelContext(container)
            ctx.autosaveEnabled = true
            do {
                let descriptor = FetchDescriptor<Contact>(
                    predicate: #Predicate<Contact> { c in c.uuid == contactUUID }
                )
                let contacts = try ctx.fetch(descriptor)
                guard let contactInBg = contacts.first else {
                    throw NSError(domain: "ManualFaceRecognition", code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "Contact not found"])
                }
                let referenceEmbeddings = try await self.getReferenceEmbeddings(for: contactInBg, in: ctx)
                let contactPhotoDate = Self.photoCaptureDate(from: contactInBg.photo) ?? contactInBg.timestamp
                let anchorDates = [contactPhotoDate] + referenceEmbeddings.map(\.photoDate)
                let allAssets = await self.fetchPhotoAssetsSortedByProximity(toAnchorDates: anchorDates)
                let assets = allAssets.filter { !alreadyProcessedAssetIds.contains($0.localIdentifier) }
                var assetIdsWithStoredFaces: Set<String> = []
                do {
                    assetIdsWithStoredFaces = try FaceAnalysisCache.fetchAssetIdentifiersWithStoredFaces(in: ctx)
                } catch { }
                let toProcess = assets.filter { !assetIdsWithStoredFaces.contains($0.localIdentifier) }
                let toMatchOnly = assets.filter { assetIdsWithStoredFaces.contains($0.localIdentifier) }
                var foundFacesCount = 0
                var processedCount = 0
                let totalToProcess = min(toProcess.count, self.initialBatchLimit)
                let stoppedEarly = toProcess.count > self.initialBatchLimit
                for batchStart in stride(from: 0, to: totalToProcess, by: self.batchSize) {
                    let batchEnd = min(batchStart + self.batchSize, totalToProcess)
                    let batch = Array(toProcess[batchStart..<batchEnd])
                    let matchCount = await self.processPhotoBatch(
                        batch,
                        referenceEmbeddings: referenceEmbeddings,
                        contactUUID: contactUUID,
                        modelContext: ctx
                    )
                    foundFacesCount += matchCount
                    processedCount += batch.count
                    await MainActor.run { progressHandler(processedCount, totalToProcess) }
                }
                let matchOnlyCount = await self.matchStoredEmbeddingsOnly(
                    assets: toMatchOnly,
                    referenceEmbeddings: referenceEmbeddings,
                    contactUUID: contactUUID,
                    modelContext: ctx
                )
                foundFacesCount += matchOnlyCount
                await MainActor.run {
                    completion(.success(foundFacesCount))
                    self.removeProcessing(contactUUID: contactUUID)
                }
                if stoppedEarly, processedCount < toProcess.count {
                    for batchStart in stride(from: totalToProcess, to: toProcess.count, by: self.batchSize) {
                        let batchEnd = min(batchStart + self.batchSize, toProcess.count)
                        let batch = Array(toProcess[batchStart..<batchEnd])
                        _ = await self.processPhotoBatch(
                            batch,
                            referenceEmbeddings: referenceEmbeddings,
                            contactUUID: contactUUID,
                            modelContext: ctx
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                    self.removeProcessing(contactUUID: contactUUID)
                }
            }
        }
    }

    // MARK: - Helpers

    private func processPhotoBatchOffMainActor(
        assetIds: [String],
        referenceEmbeddingDatas: [Data],
        contactUUID: UUID
    ) async -> [FaceMatchResult] {
        guard !referenceEmbeddingDatas.isEmpty else { return [] }
        let refDatas = referenceEmbeddingDatas
        let obsThreshold = observationDistanceThreshold
        let cosThreshold = similarityThreshold
        let service = faceRecognitionService
        return await Task.detached(priority: .userInitiated) {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
            var assets: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in assets.append(asset) }
            var matches: [FaceMatchResult] = []
            for asset in assets {
                let embeddings = await withCheckedContinuation { (continuation: CheckedContinuation<[FaceEmbedding], Never>) in
                    service.detectFacesAndGenerateEmbeddings(in: asset) { continuation.resume(returning: $0) }
                }
                for embedding in embeddings {
                    let matchesAny = refDatas.contains { refData in
                        FaceEmbedding.areSimilar(
                            embeddingData1: refData,
                            embeddingData2: embedding.embeddingData,
                            observationDistanceThreshold: obsThreshold,
                            cosineSimilarityThreshold: cosThreshold
                        )
                    }
                    if matchesAny {
                        matches.append(FaceMatchResult(
                            assetIdentifier: embedding.assetIdentifier,
                            embeddingData: embedding.embeddingData,
                            boundingBox: embedding.boundingBox,
                            qualityScore: embedding.qualityScore,
                            photoDate: embedding.photoDate,
                            thumbnailData: embedding.thumbnailData,
                            yaw: embedding.yaw,
                            pitch: embedding.pitch,
                            roll: embedding.roll
                        ))
                    }
                }
            }
            if !matches.isEmpty {
                print("[FaceRecognition] processPhotoBatchOffMainActor: \(matches.count) match(es)")
            }
            return matches
        }.value
    }

    private func insertFaceMatchResults(
        _ results: [FaceMatchResult],
        contactUUID: UUID,
        modelContext: ModelContext
    ) {
        let searchUUID: UUID? = contactUUID
        let descriptor = FetchDescriptor<FaceEmbedding>(
            predicate: #Predicate<FaceEmbedding> { embed in embed.contactUUID == searchUUID }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingAssetIds = Set(existing.map(\.assetIdentifier))

        for r in results {
            if existingAssetIds.contains(r.assetIdentifier) { continue }
            let embedding = FaceEmbedding(
                assetIdentifier: r.assetIdentifier,
                contactUUID: contactUUID,
                embeddingData: r.embeddingData,
                boundingBox: r.boundingBox,
                qualityScore: r.qualityScore,
                yaw: r.yaw, pitch: r.pitch, roll: r.roll, photoDate: r.photoDate,
                isManuallyVerified: false,
                thumbnailData: r.thumbnailData
            )
            modelContext.insert(embedding)
        }
        try? modelContext.save()
    }

    private func processPhotoBatch(
        _ assets: [PHAsset],
        referenceEmbeddings: [FaceEmbedding],
        contactUUID: UUID,
        modelContext: ModelContext
    ) async -> Int {
        let refDatas = referenceEmbeddings.map(\.embeddingData)
        let assetIds = assets.map(\.localIdentifier)
        let results = await processPhotoBatchOffMainActor(assetIds: assetIds, referenceEmbeddingDatas: refDatas, contactUUID: contactUUID)
        await MainActor.run {
            insertFaceMatchResults(results, contactUUID: contactUUID, modelContext: modelContext)
        }
        return results.count
    }

    private func matchStoredEmbeddingsOnly(
        assets: [PHAsset],
        referenceEmbeddings: [FaceEmbedding],
        contactUUID: UUID,
        modelContext: ModelContext
    ) async -> Int {
        guard !referenceEmbeddings.isEmpty else { return 0 }
        let refDatas = referenceEmbeddings.map(\.embeddingData)
        let obsThresh = observationDistanceThreshold
        let cosThresh = similarityThreshold
        var assigned = 0
        for asset in assets {
            let embeddings: [FaceEmbedding]
            do {
                embeddings = try FaceAnalysisCache.fetchStoredEmbeddings(forAssetIdentifier: asset.localIdentifier, in: modelContext)
            } catch {
                continue
            }
            for embed in embeddings {
                guard embed.contactUUID == nil else { continue }
                let matchesAny = refDatas.contains { refData in
                    FaceEmbedding.areSimilar(
                        embeddingData1: refData,
                        embeddingData2: embed.embeddingData,
                        observationDistanceThreshold: obsThresh,
                        cosineSimilarityThreshold: cosThresh
                    )
                }
                if matchesAny {
                    embed.contactUUID = contactUUID
                    embed.isManuallyVerified = false
                    assigned += 1
                }
            }
        }
        if assigned > 0 {
            try? modelContext.save()
        }
        return assigned
    }

    @MainActor
    private func getReferenceEmbeddings(for contact: Contact, in modelContext: ModelContext) async throws -> [FaceEmbedding] {
        let descriptor = FetchDescriptor<FaceEmbedding>()
        guard let all = try? modelContext.fetch(descriptor) else { return [] }
        let existingForContact = all.filter { $0.contactUUID == contact.uuid }
        let verified = existingForContact.filter { $0.isManuallyVerified }
        if !verified.isEmpty {
            print("[FaceRecognition] getReferenceEmbeddings: using \(verified.count) confirmed embedding(s)")
            return verified
        }
        let one = try await getReferenceEmbedding(for: contact, in: modelContext)
        return [one]
    }

    @MainActor
    private func getReferenceEmbedding(for contact: Contact, in modelContext: ModelContext) async throws -> FaceEmbedding {
        let descriptor = FetchDescriptor<FaceEmbedding>()
        guard let allEmbeddings = try? modelContext.fetch(descriptor) else { throw NSError(domain: "ManualFaceRecognition", code: -5, userInfo: [NSLocalizedDescriptionKey: "Fetch failed"]) }
        if let existingEmbedding = allEmbeddings.first(where: { $0.contactUUID == contact.uuid && $0.isManuallyVerified }) {
            print("[FaceRecognition] getReferenceEmbedding: using existing embedding uuid=\(existingEmbedding.uuid)")
            return existingEmbedding
        }
        print("[FaceRecognition] getReferenceEmbedding: generating from contact photo (size=\(contact.photo.count) bytes)")
        guard let photoImage = UIImage(data: contact.photo) else {
            throw NSError(domain: "ManualFaceRecognition", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid contact photo"])
        }
        let assetId = "contact-\(contact.uuid.uuidString)"
        let photoDate = contact.timestamp
        let imageRef = SendableRef(photoImage)
        let embeddings = await withCheckedContinuation { continuation in
            faceRecognitionService.detectFacesAndGenerateEmbeddings(
                in: imageRef.value,
                assetIdentifier: assetId,
                photoDate: photoDate
            ) { embeddings in
                continuation.resume(returning: embeddings)
            }
        }
        guard let embedding = embeddings.first else {
            throw NSError(domain: "ManualFaceRecognition", code: -3,
                         userInfo: [NSLocalizedDescriptionKey: "No face detected in contact photo"])
        }
        embedding.contactUUID = contact.uuid
        embedding.isManuallyVerified = true
        embedding.isRepresentative = true
        modelContext.insert(embedding)
        try modelContext.save()
        return embedding
    }

    private func fetchPhotoAssets() async -> [PHAsset] {
        await withCheckedContinuation { continuation in
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            let results = PHAsset.fetchAssets(with: options)
            var assets: [PHAsset] = []
            results.enumerateObjects { asset, _, _ in assets.append(asset) }
            continuation.resume(returning: assets)
        }
    }

    private static func photoCaptureDate(from imageData: Data) -> Date? {
        guard !imageData.isEmpty,
              let source = CGImageSourceCreateWithData(imageData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }
        if let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            let dateString = (exif[kCGImagePropertyExifDateTimeOriginal as String] as? String)
                ?? (exif[kCGImagePropertyExifDateTimeDigitized as String] as? String)
            if let dateString = dateString, let date = Self.parseEXIFDate(dateString) { return date }
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
           let dateString = tiff[kCGImagePropertyTIFFDateTime as String] as? String {
            return Self.parseEXIFDate(dateString)
        }
        return nil
    }

    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private static func parseEXIFDate(_ string: String) -> Date? {
        exifDateFormatter.date(from: string)
    }

    private func fetchPhotoAssetsSortedByProximity(toAnchorDates anchorDates: [Date]) async -> [PHAsset] {
        let assets = await fetchPhotoAssets()
        guard !anchorDates.isEmpty else { return assets }
        let refs = anchorDates.map(\.timeIntervalSince1970)
        return assets.sorted { a, b in
            let ta = a.creationDate?.timeIntervalSince1970 ?? .infinity
            let tb = b.creationDate?.timeIntervalSince1970 ?? .infinity
            let distA = refs.map { abs(ta - $0) }.min() ?? .infinity
            let distB = refs.map { abs(tb - $0) }.min() ?? .infinity
            return distA < distB
        }
    }
}
