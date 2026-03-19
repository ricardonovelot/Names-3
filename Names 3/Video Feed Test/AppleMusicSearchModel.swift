import Foundation
import SwiftUI
import Combine
import MusicKit

@MainActor
final class AppleMusicSearchModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var results: [AppleCatalogSong] = []
    @Published private(set) var error: String?
    /// True after a search completes (success or empty); used to show "No results" vs library.
    @Published private(set) var hasSearched: Bool = false

    private var task: Task<Void, Never>?

    var canSearch: Bool {
        AppleMusicCatalog.isConfigured && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching
    }

    func submitSearch(limit: Int = 15) {
        task?.cancel()
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            results = []
            error = nil
            return
        }
        Diagnostics.log("AMSearch.submit term=\"\(term)\"")
        isSearching = true
        error = nil
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // MusicKit catalog search requires MusicAuthorization; request before first search.
                if MusicAuthorization.currentStatus == .notDetermined {
                    _ = await MusicAuthorization.request()
                }
                let res = try await AppleMusicCatalog.shared.search(term: term, limit: limit)
                if Task.isCancelled { return }
                await MainActor.run {
                    Diagnostics.log("AMSearch.done count=\(res.count)")
                    self.results = res
                    self.isSearching = false
                    self.error = nil
                    self.hasSearched = true
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    Diagnostics.log("AMSearch.error \(error.localizedDescription)")
                    self.results = []
                    self.error = Self.userFriendlyMessage(for: error)
                    self.isSearching = false
                    self.hasSearched = true
                }
            }
        }
    }

    private static func userFriendlyMessage(for error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("notdetermined") || msg.contains("country code") || msg.contains("authorization") {
            return "Allow Apple Music access to search the catalog."
        }
        if msg.contains("denied") || msg.contains("restricted") {
            return "Apple Music access was denied. Open Settings to allow."
        }
        if msg.contains("network") || msg.contains("connection") || msg.contains("offline") {
            return "Check your connection and try again."
        }
        if msg.isEmpty || msg == "unknown error" || msg.contains("unknown") {
            return "Search unavailable. Try again."
        }
        return error.localizedDescription
    }

    func cancelSearch() {
        task?.cancel()
        task = nil
        isSearching = false
    }

    func clear() {
        cancelSearch()
        query = ""
        results = []
        error = nil
        hasSearched = false
    }
}