import Foundation
import SwiftUI
import Combine

@MainActor
final class AppleMusicSearchModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var results: [AppleCatalogSong] = []
    @Published private(set) var error: String?

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
                let res = try await AppleMusicCatalog.shared.search(term: term, limit: limit)
                if Task.isCancelled { return }
                await MainActor.run {
                    Diagnostics.log("AMSearch.done count=\(res.count)")
                    self.results = res
                    self.isSearching = false
                    if res.isEmpty {
                        self.error = nil
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    Diagnostics.log("AMSearch.error \(error.localizedDescription)")
                    self.results = []
                    self.error = error.localizedDescription
                    self.isSearching = false
                }
            }
        }
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
    }
}