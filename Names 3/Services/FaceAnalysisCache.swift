//
//  FaceAnalysisCache.swift
//  Names 3
//
//  Single source of truth for "has this asset been analyzed?" and reuse of stored
//  face embeddings. Ensures we never run Vision twice on the same image and
//  that Name Faces / Find Similar reuse existing data (Apple Photos–style).
//

import Foundation
import SwiftData
import Photos

/// Provides global "asset already analyzed" checks and stored-embedding lookup
/// so we avoid duplicate face detection and immediately recognize known faces.
enum FaceAnalysisCache {
    
    // MARK: - Already processed (any contact)
    
    /// Returns true if we have at least one FaceEmbedding for this asset (library asset only).
    /// "name-faces-*" identifiers are not considered (onboarding/manual crops).
    static func hasStoredFaces(
        forAssetIdentifier assetIdentifier: String,
        in modelContext: ModelContext
    ) -> Bool {
        guard !assetIdentifier.hasPrefix("name-faces-") else { return false }
        var descriptor = FetchDescriptor<FaceEmbedding>(
            predicate: #Predicate<FaceEmbedding> { $0.assetIdentifier == assetIdentifier }
        )
        let limit = 1
        descriptor.fetchLimit = limit
        return (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }
    
    /// Returns all stored face embeddings for an asset, sorted by bounding box (top-left order)
    /// so face index is stable. Use for Name Faces pre-fill and for matching without re-running Vision.
    static func fetchStoredEmbeddings(
        forAssetIdentifier assetIdentifier: String,
        in modelContext: ModelContext
    ) throws -> [FaceEmbedding] {
        let descriptor = FetchDescriptor<FaceEmbedding>(
            predicate: #Predicate<FaceEmbedding> { $0.assetIdentifier == assetIdentifier }
        )
        var list = try modelContext.fetch(descriptor)
        list.sort { a, b in
            let aY = a.boundingBox.count >= 2 ? a.boundingBox[1] : 0
            let bY = b.boundingBox.count >= 2 ? b.boundingBox[1] : 0
            if aY != bY { return aY > bY } // Vision origin bottom-left: larger Y = higher on screen
            let aX = a.boundingBox.count >= 1 ? a.boundingBox[0] : 0
            let bX = b.boundingBox.count >= 1 ? b.boundingBox[0] : 0
            return aX < bX
        }
        return list
    }
    
    /// Max FaceEmbedding rows to scan for "all assets with stored faces". Prevents unbounded fetch on large DBs.
    private static let maxAssetIdentifiersFetchLimit = 50_000

    /// Returns the set of asset identifiers that already have at least one FaceEmbedding (library only).
    /// Use when batching "Find Similar" to skip re-processing. Capped to avoid very long fetches.
    static func fetchAssetIdentifiersWithStoredFaces(
        in modelContext: ModelContext
    ) throws -> Set<String> {
        var descriptor = FetchDescriptor<FaceEmbedding>(
            sortBy: [SortDescriptor(\.assetIdentifier)]
        )
        descriptor.fetchLimit = maxAssetIdentifiersFetchLimit
        let list = try modelContext.fetch(descriptor)
        return Set(list.map(\.assetIdentifier).filter { !$0.hasPrefix("name-faces-") })
    }

    /// For a batch of assets, returns which have stored faces. Fetches only FaceEmbeddings for those asset IDs.
    static func assetIdentifiersWithStoredFaces(
        from assets: [PHAsset],
        in modelContext: ModelContext
    ) throws -> Set<String> {
        let ids = Set(assets.map(\.localIdentifier))
        guard !ids.isEmpty else { return [] }
        let idArray = Array(ids)
        let descriptor = FetchDescriptor<FaceEmbedding>(
            predicate: #Predicate<FaceEmbedding> { e in idArray.contains(e.assetIdentifier) }
        )
        let list = try modelContext.fetch(descriptor)
        return Set(list.map(\.assetIdentifier))
    }
}
