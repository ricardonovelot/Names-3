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
        guard let devToken = Bundle.main.object(forInfoDictionaryKey: "APPLE_MUSIC_DEVELOPER_TOKEN") as? String, !devToken.isEmpty else {
            lastError = "Missing APPLE_MUSIC_DEVELOPER_TOKEN in Info.plist."
            return
        }
        // MusicKit manages tokens for MusicDataRequest. For custom API calls that need a user token,
        // use MusicDataRequest with the framework's token provider, or keep StoreKit for legacy flows.
        // This method is retained for compatibility; consider migrating to MusicKit's request APIs.
        lastError = "User token requests: use MusicKit's MusicDataRequest for catalog operations."
    }
}
