import Foundation
import MusicKit
import Combine

@MainActor
final class AppleMusicAuth: ObservableObject {
    @Published private(set) var authStatus: MusicAuthorization.Status = .notDetermined
    @Published private(set) var canPlayCatalogContent: Bool = false
    @Published private(set) var canAddToCloudLibrary: Bool = false
    @Published private(set) var userToken: String?
    @Published private(set) var lastError: String?

    private let keychain = KeychainStore(service: "VideoFeedTest.AppleMusic")
    private let userTokenKey = "appleMusic.userToken"

    init() {
        if let data = try? keychain.getData(key: userTokenKey), let token = String(data: data, encoding: .utf8) {
            self.userToken = token
        }
        Task { await refresh() }
    }

    var isAuthorized: Bool { authStatus == .authorized }
    var hasCatalogPlayback: Bool { canPlayCatalogContent }

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        authStatus = status
        if status == .authorized {
            await refresh()
        }
    }

    func refresh() async {
        authStatus = MusicAuthorization.currentStatus
        do {
            let subscription = try await MusicSubscription.current
            canPlayCatalogContent = subscription.canPlayCatalogContent
            canAddToCloudLibrary = subscription.hasCloudLibraryEnabled
            lastError = nil
        } catch {
            canPlayCatalogContent = false
            canAddToCloudLibrary = false
            lastError = error.localizedDescription
        }
    }

    func requestUserTokenIfPossible() async {
        // MusicKit manages tokens for MusicDataRequest and catalog operations.
        // Use MusicCatalogSearchRequest or MusicDataRequest for catalog search; no manual token needed.
        lastError = "User token requests: use MusicKit's MusicDataRequest for catalog operations."
    }
}
