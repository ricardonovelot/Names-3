//
//  AlbumStore.swift
//  Names 3
//
//  Persists albums and individual assets. Format: "album:localId" or "asset:localId".
//  Legacy IDs without prefix are treated as albums.
//
//  Sync strategy: SwiftData + CloudKit — same as contacts, notes, etc. Albums sync
//  reliably across devices. Migrates from legacy NSUbiquitousKeyValueStore on first run.
//

import Foundation
import Photos
import Combine
import SwiftData
import UIKit
import CoreData

// MARK: - ProfileItem

enum ProfileItem: Hashable {
    case album(PHAssetCollection)
    case asset(PHAsset)

    var identifier: String {
        switch self {
        case .album(let c): return "album:\(c.localIdentifier)"
        case .asset(let a): return "asset:\(a.localIdentifier)"
        }
    }

    var displayTitle: String? {
        switch self {
        case .album(let c): return c.localizedTitle
        case .asset: return nil
        }
    }

    var assetCount: Int {
        switch self {
        case .album(let c):
            let n = c.estimatedAssetCount
            return n == NSNotFound ? 0 : n
        case .asset: return 1
        }
    }
}

// MARK: - AlbumStore

@MainActor
final class AlbumStore: ObservableObject {

    static let shared = AlbumStore()

    private static let itemsKey = "com.names3.albums.savedIdentifiers"
    private static let carouselSignaturesKey = "com.names3.albums.carouselSignatures"
    private static let migratedFromKVKey = "com.names3.albums.migratedFromKV"

    private let kvStore = NSUbiquitousKeyValueStore.default

    @Published private(set) var savedIdentifiers: [String] = []

    private var modelContext: ModelContext?
    private var remoteChangeObserver: NSObjectProtocol?

    private init() {
        observeRemoteStoreChanges()
    }

    /// Call once when ModelContainer is ready. Migrates from KV store on first run.
    func configure(container: ModelContainer) {
        guard modelContext == nil else { return }
        modelContext = ModelContext(container)

        if !UserDefaults.standard.bool(forKey: Self.migratedFromKVKey) {
            migrateFromKVStore()
        }

        refreshFromStore()
    }

    // MARK: - Migration from KV store

    private func migrateFromKVStore() {
        guard let context = modelContext else { return }

        let kvItems = kvStore.array(forKey: Self.itemsKey) as? [String]
            ?? UserDefaults.standard.stringArray(forKey: Self.itemsKey)
        let kvSigs = kvStore.dictionary(forKey: Self.carouselSignaturesKey) as? [String: String]
            ?? UserDefaults.standard.dictionary(forKey: Self.carouselSignaturesKey) as? [String: String]

        if let items = kvItems, !items.isEmpty {
            for (index, id) in items.enumerated() {
                let entry = SavedAlbum(identifier: id, sortOrder: index)
                context.insert(entry)
            }
        }
        if let sigs = kvSigs {
            for (sig, albumId) in sigs {
                let mapping = SavedCarouselMapping(carouselSignature: sig, albumIdentifier: albumId)
                context.insert(mapping)
            }
        }

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: Self.migratedFromKVKey)
            kvStore.removeObject(forKey: Self.itemsKey)
            kvStore.removeObject(forKey: Self.carouselSignaturesKey)
            kvStore.synchronize()
        } catch {
            // Migration failed; will retry next launch or user starts fresh
        }
    }

    // MARK: - SwiftData sync observation

    private func observeRemoteStoreChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromStore()
            }
        }
    }

    deinit {
        if let obs = remoteChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private static func carouselSignature(for assets: [PHAsset]) -> String {
        assets.map(\.localIdentifier).sorted().joined(separator: ",")
    }

    // MARK: - Store access

    /// Call when CloudKit sync brings in remote changes. Refreshes from SwiftData store.
    func refreshFromRemoteSync() {
        refreshFromStore()
    }

    private func refreshFromStore() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<SavedAlbum>(sortBy: [SortDescriptor(\.sortOrder)])
        let entries = (try? context.fetch(descriptor)) ?? []
        let ids = entries.map(\.identifier)
        if ids != savedIdentifiers {
            savedIdentifiers = ids
        }
    }

    private var carouselSignatures: [String: String] {
        get {
            guard let context = modelContext else { return [:] }
            let descriptor = FetchDescriptor<SavedCarouselMapping>()
            let mappings = (try? context.fetch(descriptor)) ?? []
            return Dictionary(uniqueKeysWithValues: mappings.map { ($0.carouselSignature, $0.albumIdentifier) })
        }
        set {
            guard let context = modelContext else { return }
            let descriptor = FetchDescriptor<SavedCarouselMapping>()
            let existing = (try? context.fetch(descriptor)) ?? []
            for m in existing { context.delete(m) }
            for (sig, albumId) in newValue {
                context.insert(SavedCarouselMapping(carouselSignature: sig, albumIdentifier: albumId))
            }
            try? context.save()
            refreshFromStore()
        }
    }

    private func persistIdentifiers(_ ids: [String]) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<SavedAlbum>()
        let existing = (try? context.fetch(descriptor)) ?? []
        for e in existing { context.delete(e) }
        for (index, id) in ids.enumerated() {
            context.insert(SavedAlbum(identifier: id, sortOrder: index))
        }
        try? context.save()
        savedIdentifiers = ids
    }

    // MARK: - Public API

    func addAlbum(_ collection: PHAssetCollection) {
        let id = "album:\(collection.localIdentifier)"
        guard !savedIdentifiers.contains(id) else { return }
        var ids = savedIdentifiers
        ids.append(id)
        persistIdentifiers(ids)
    }

    func addAsset(_ asset: PHAsset) {
        let id = "asset:\(asset.localIdentifier)"
        guard !savedIdentifiers.contains(id) else { return }
        var ids = savedIdentifiers
        ids.append(id)
        persistIdentifiers(ids)
    }

    /// Creates a new album in the photo library with the given assets and adds it to the store.
    func addAlbumFromAssets(_ assets: [PHAsset], title: String) {
        guard !assets.isEmpty else { return }
        var placeholderId: String?
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            placeholderId = request.placeholderForCreatedAssetCollection.localIdentifier
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assets.map(\.localIdentifier), options: nil)
            request.addAssets(fetchResult as NSFastEnumeration)
        } completionHandler: { [weak self] success, _ in
            guard success, let self, let id = placeholderId else { return }
            Task { @MainActor in
                let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil)
                if let collection = result.firstObject {
                    self.addAlbum(collection)
                    let sig = Self.carouselSignature(for: assets)
                    var map = self.carouselSignatures
                    map[sig] = collection.localIdentifier
                    self.carouselSignatures = map
                }
            }
        }
    }

    func removeCarousel(assets: [PHAsset]) {
        let sig = Self.carouselSignature(for: assets)
        guard let albumId = carouselSignatures[sig] else { return }
        var map = carouselSignatures
        map.removeValue(forKey: sig)
        carouselSignatures = map
        removeItem(withIdentifier: "album:\(albumId)")
    }

    func removeItem(withIdentifier id: String) {
        var ids = savedIdentifiers
        ids.removeAll { $0 == id }
        if id.hasPrefix("album:") {
            let albumId = String(id.dropFirst(6))
            var map = carouselSignatures
            for (sig, aid) in map where aid == albumId {
                map.removeValue(forKey: sig)
                break
            }
            carouselSignatures = map
        }
        persistIdentifiers(ids)
    }

    /// True if the single asset is in the store.
    func isAssetSaved(_ asset: PHAsset) -> Bool {
        contains(asset)
    }

    /// True if we have an album created from this exact carousel.
    func isCarouselSaved(_ assets: [PHAsset]) -> Bool {
        guard assets.count > 1 else {
            return assets.count == 1 ? contains(assets[0]) : false
        }
        let sig = Self.carouselSignature(for: assets)
        guard let albumId = carouselSignatures[sig] else { return false }
        return savedIdentifiers.contains("album:\(albumId)")
    }

    func removeAlbums(at offsets: IndexSet) {
        var ids = savedIdentifiers
        ids.remove(atOffsets: offsets)
        persistIdentifiers(ids)
    }

    func contains(_ collection: PHAssetCollection) -> Bool {
        savedIdentifiers.contains("album:\(collection.localIdentifier)")
    }

    func contains(_ asset: PHAsset) -> Bool {
        savedIdentifiers.contains("asset:\(asset.localIdentifier)")
    }

    /// Resolves persisted identifiers to ProfileItems (skips deleted items).
    func resolvedItems() -> [ProfileItem] {
        savedIdentifiers.compactMap { id -> ProfileItem? in
            if id.hasPrefix("asset:") {
                let localId = String(id.dropFirst(6))
                guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil).firstObject else {
                    return nil
                }
                return .asset(asset)
            }
            let localId = id.hasPrefix("album:") ? String(id.dropFirst(6)) : id
            guard let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [localId],
                options: nil
            ).firstObject else { return nil }
            return .album(collection)
        }
    }

    /// Legacy: resolved collections only (for backward compat).
    func resolvedCollections() -> [PHAssetCollection] {
        resolvedItems().compactMap { item in
            if case .album(let c) = item { return c }
            return nil
        }
    }
}
