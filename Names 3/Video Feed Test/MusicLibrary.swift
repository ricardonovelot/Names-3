import Foundation
import MediaPlayer
import SwiftUI
import Combine

@MainActor
final class MusicLibraryModel: ObservableObject {
    @Published var authorization: MPMediaLibraryAuthorizationStatus = MPMediaLibrary.authorizationStatus()
    @Published var isLoading = false
    @Published var lastAdded: [MPMediaItem] = []

    @Published var isGoogleConnected = false
    @Published var isGoogleSyncing = false
    @Published var googleStatusMessage: String?
    @Published var catalogMatches: [AppleCatalogSong] = []
    @Published var lastGoogleSyncAt: Date?

    private var cancellables = Set<AnyCancellable>()

    func bootstrap() {
        authorization = MPMediaLibrary.authorizationStatus()
        Diagnostics.log("MusicLibrary.bootstrap: auth=\(authorization.rawValue) starting restore")

        Task { @MainActor in
            // Adopt prefetched cache if available
            let snap = await MusicLibraryCache.shared.snapshotLastAdded()
            if self.lastAdded.isEmpty, !snap.items.isEmpty {
                self.lastAdded = snap.items
                Diagnostics.log("MusicLibrary.bootstrap: adopted cached lastAdded=\(snap.items.count)")
            }

            let connected = await GoogleAuth.shared.restore()
            Diagnostics.log("MusicLibrary.bootstrap: restore connected=\(connected)")
            self.isGoogleConnected = connected
            if connected {
                await self.refreshGoogleLikes(limit: 15)
            } else if authorization == .authorized, self.lastAdded.isEmpty {
                self.loadLastAdded(limit: 15)
            }
        }
    }

    func requestAccessAndLoad() {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.authorization = status
                if status == .authorized, !self.isGoogleConnected {
                    self.loadLastAdded(limit: 15)
                }
            }
        }
    }

    func loadLastAdded(limit: Int = 15) {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let items = MPMediaQuery.songs().items ?? []
            let sorted = items.sorted { a, b in
                a.dateAdded > b.dateAdded
            }
            let filtered = sorted.filter { $0.playbackDuration > 0.1 }
            let picks = Array(filtered.prefix(limit))
            await MainActor.run {
                self.lastAdded = picks
                self.isLoading = false
            }
        }
    }

    func connectGoogle() {
        Task { @MainActor in
            let ready = await GoogleAuth.shared.isReady
            Diagnostics.log("MusicLibrary.connectGoogle: ready=\(ready)")
            guard ready else {
                self.googleStatusMessage = "Google not configured. Set GOOGLE_CLIENT_ID in Info.plist and add the reversed client ID URL scheme."
                self.isGoogleConnected = false
                return
            }

            isGoogleSyncing = true
            googleStatusMessage = "Connecting Google…"
            Diagnostics.log("MusicLibrary.connectGoogle: starting signIn()")
            do {
                let ok = try await GoogleAuth.shared.signIn()
                Diagnostics.log("MusicLibrary.connectGoogle: signIn ok=\(ok)")
                self.isGoogleConnected = ok
                if ok {
                    await self.refreshGoogleLikes(limit: 15)
                } else {
                    self.googleStatusMessage = "Google connection cancelled."
                }
            } catch {
                Diagnostics.log("MusicLibrary.connectGoogle: signIn error=\(error.localizedDescription)")
                self.googleStatusMessage = "Google sign-in failed: \(error.localizedDescription)"
            }
            isGoogleSyncing = false
        }
    }

    func disconnectGoogle() {
        Task { @MainActor in
            Diagnostics.log("MusicLibrary.disconnectGoogle")
            await GoogleAuth.shared.signOut()
            isGoogleConnected = false
            lastGoogleSyncAt = nil
            googleStatusMessage = "Disconnected."
            catalogMatches = []
            if authorization == .authorized {
                loadLastAdded(limit: 15)
            } else {
                lastAdded = []
            }
        }
    }

    func retryGoogleSync() {
        Task { @MainActor in
            guard isGoogleConnected, !isGoogleSyncing else {
                Diagnostics.log("MusicLibrary.retryGoogleSync: ignored connected=\(isGoogleConnected) syncing=\(isGoogleSyncing)")
                return
            }
            Diagnostics.log("MusicLibrary.retryGoogleSync: retrying")
            googleStatusMessage = "Retrying sync…"
            await refreshGoogleLikes(limit: 15)
        }
    }

    func refreshGoogleLikes(limit: Int = 15) async {
        isGoogleSyncing = true
        googleStatusMessage = "Fetching YouTube likes…"
        Diagnostics.log("MusicLibrary.refreshGoogleLikes: begin limit=\(limit)")
        defer {
            isGoogleSyncing = false
            Diagnostics.log("MusicLibrary.refreshGoogleLikes: end")
        }

        guard await GoogleAuth.shared.isReady else {
            Diagnostics.log("MusicLibrary.refreshGoogleLikes: Google not configured")
            googleStatusMessage = "Google not configured. Set clientID and redirect URI."
            if authorization == .authorized {
                loadLastAdded(limit: limit)
            }
            return
        }

        func fetchAndMatch() async throws {
            let tracks = try await YouTubeAPI.shared.fetchRecentLikedTracks(limit: 25)
            Diagnostics.log("MusicLibrary.refreshGoogleLikes: fetched \(tracks.count) tracks")

            if AppleMusicCatalog.isConfigured {
                do {
                    let catalog = try await AppleMusicCatalog.shared.match(tracks: tracks, limit: limit)
                    Diagnostics.log("MusicLibrary.refreshGoogleLikes: catalog matches=\(catalog.count)")
                    if !catalog.isEmpty {
                        await MainActor.run {
                            self.catalogMatches = catalog
                            self.lastAdded = []
                            self.googleStatusMessage = "Showing your latest likes from Apple Music."
                            self.lastGoogleSyncAt = Date()
                        }
                        return
                    }
                } catch {
                    Diagnostics.log("MusicLibrary.refreshGoogleLikes: catalog match error=\(error.localizedDescription)")
                }
            }

            let matchedLocal = try await SongMatcher.shared.match(tracks: tracks, limit: limit)
            Diagnostics.log("MusicLibrary.refreshGoogleLikes: local matches=\(matchedLocal.count)")
            await MainActor.run {
                if matchedLocal.isEmpty {
                    self.googleStatusMessage = "No close matches found in Apple Music or your library."
                    if self.authorization == .authorized {
                        self.loadLastAdded(limit: limit)
                    } else {
                        self.lastAdded = []
                        self.catalogMatches = []
                    }
                } else {
                    self.googleStatusMessage = "Showing your latest likes."
                    self.lastAdded = matchedLocal
                    self.catalogMatches = []
                }
                self.lastGoogleSyncAt = Date()
            }
        }

        do {
            try await fetchAndMatch()
        } catch {
            if let nsErr = error as NSError?, nsErr.domain == "GoogleAuth", nsErr.code == -20 {
                Diagnostics.log("MusicLibrary.refreshGoogleLikes: not signed in → re-consent")
                do {
                    _ = try await GoogleAuth.shared.signIn()
                    try await fetchAndMatch()
                    return
                } catch {
                    Diagnostics.log("MusicLibrary.refreshGoogleLikes: re-consent failed \(error.localizedDescription)")
                    await MainActor.run {
                        self.isGoogleConnected = false
                        self.googleStatusMessage = "Google re-consent required: \(error.localizedDescription)"
                    }
                }
            } else if let apiErr = error as? YouTubeAPI.APIError {
                switch apiErr {
                case .http(let code, let message, let reason):
                    Diagnostics.log("MusicLibrary.refreshGoogleLikes: HTTP error \(code) \(message) reason=\(String(describing: reason))")
                    if code == 401 || code == 403 {
                        do {
                            _ = try await GoogleAuth.shared.signIn()
                            try await fetchAndMatch()
                            return
                        } catch {
                            Diagnostics.log("MusicLibrary.refreshGoogleLikes: re-consent failed \(error.localizedDescription)")
                            await MainActor.run {
                                self.isGoogleConnected = false
                                self.googleStatusMessage = "Google re-consent failed: \(error.localizedDescription)"
                            }
                        }
                    }
                default:
                    break
                }
            }
            await MainActor.run {
                self.googleStatusMessage = "Failed to load likes: \(error.localizedDescription)"
                if self.authorization == .authorized {
                    self.loadLastAdded(limit: limit)
                }
            }
        }
    }

    func play(_ item: MPMediaItem) {
        AppleMusicController.shared.play(item: item)
    }

    func artwork(for item: MPMediaItem, size: CGSize) -> UIImage? {
        item.artwork?.image(at: size)
    }
}