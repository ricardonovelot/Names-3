//
//  NameFacesMemory.swift
//  Names 3
//
//  Lightweight persistence of (asset, face index) -> (name, contact) for Name Faces.
//  Remembers already-named faces so the app can restore when the user returns to a photo.
//  Memory-conscious: cap at 100 assets, store only strings/UUIDs, persist to UserDefaults.
//

import Foundation

/// Remembers face name assignments per photo (asset + face index) so we can restore when the user comes back to a photo.
/// Capped at 100 assets; evicts oldest to limit memory and disk.
enum NameFacesMemory {
    private static let key = "NameFacesMemory.assignments"
    private static let orderKey = "NameFacesMemory.order"
    private static let maxAssets = 100
    private static let queue = DispatchQueue(label: "NameFacesMemory", qos: .userInitiated)
    
    /// One entry per face: "n" = name, "u" = contact UUID string (empty if none). Keeps payload small.
    private struct StoredRow: Codable {
        let n: String
        let u: String
    }
    private static func loadFromUserDefaults() -> (assignments: [String: [StoredRow]], order: [String]) {
        queue.sync {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([String: [StoredRow]].self, from: data),
                  let orderData = UserDefaults.standard.data(forKey: orderKey),
                  let order = try? JSONDecoder().decode([String].self, from: orderData) else {
                return ([:], [])
            }
            return (decoded, order)
        }
    }
    
    private static func saveToUserDefaults(assignments: [String: [StoredRow]], order: [String]) {
        queue.async {
            if let data = try? JSONEncoder().encode(assignments), let orderData = try? JSONEncoder().encode(order) {
                UserDefaults.standard.set(data, forKey: key)
                UserDefaults.standard.set(orderData, forKey: orderKey)
            }
        }
    }
    
    /// Returns saved names and contact UUIDs by face index for this asset. Call from main thread.
    static func getAssignments(assetIdentifier: String, faceCount: Int) -> (names: [String], contactUUIDsByIndex: [Int: UUID]) {
        let (assignments, _) = loadFromUserDefaults()
        guard let rows = assignments[assetIdentifier], !rows.isEmpty else {
            return (Array(repeating: "", count: faceCount), [:])
        }
        var names: [String] = (0..<faceCount).map { i in i < rows.count ? rows[i].n : "" }
        var contactUUIDsByIndex: [Int: UUID] = [:]
        for (i, row) in rows.enumerated() where i < faceCount && !row.u.isEmpty {
            if let uuid = UUID(uuidString: row.u) {
                contactUUIDsByIndex[i] = uuid
            }
        }
        return (names, contactUUIDsByIndex)
    }
    
    /// Saves names and contact UUIDs by face index for this asset. Evicts oldest if over cap. Call from main thread.
    static func setAssignments(assetIdentifier: String, names: [String], contactUUIDsByIndex: [Int: UUID]) {
        var (assignments, order) = loadFromUserDefaults()
        let rows: [StoredRow] = (0..<names.count).map { i in
            StoredRow(n: names[i], u: contactUUIDsByIndex[i]?.uuidString ?? "")
        }
        assignments[assetIdentifier] = rows
        order.removeAll { $0 == assetIdentifier }
        order.append(assetIdentifier)
        while order.count > maxAssets, let first = order.first {
            order.removeFirst()
            assignments[first] = nil
        }
        saveToUserDefaults(assignments: assignments, order: order)
    }
}
