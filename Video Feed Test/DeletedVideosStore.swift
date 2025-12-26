import Foundation
import Photos

actor DeletedVideosStore {
    static let shared = DeletedVideosStore()
    private let key = "deleted_videos_v1"
    private var ids: Set<String>

    init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func all() -> Set<String> { ids }

    func hide(id: String) {
        ids.insert(id)
        persist()
        notify()
    }

    func unhide(id: String) {
        ids.remove(id)
        persist()
        notify()
    }

    func unhideAll() {
        ids.removeAll()
        persist()
        notify()
    }

    func purge(ids idsToDelete: [String]) async throws {
        guard !idsToDelete.isEmpty else { return }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: idsToDelete, options: nil)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }, completionHandler: { success, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: ()) }
            })
        }
        for id in idsToDelete { ids.remove(id) }
        persist()
        notify()
    }

    private func persist() {
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    private func notify() {
        NotificationCenter.default.post(name: .deletedVideosChanged, object: nil)
    }

    nonisolated static func snapshot() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "deleted_videos_v1") ?? [])
    }
}

extension Notification.Name {
    static let deletedVideosChanged = Notification.Name("DeletedVideosChanged")
}