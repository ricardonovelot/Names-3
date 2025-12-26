import Foundation
import StoreKit
import Combine

@MainActor
final class AppleMusicAuth: ObservableObject {
    @Published private(set) var authStatus: SKCloudServiceAuthorizationStatus = SKCloudServiceController.authorizationStatus()
    @Published private(set) var capabilities: SKCloudServiceCapability = []
    @Published private(set) var userToken: String?
    @Published private(set) var lastError: String?

    private let keychain = KeychainStore(service: "VideoFeedTest.AppleMusic")
    private let userTokenKey = "appleMusic.userToken"

    init() {
        if let data = try? keychain.getData(key: userTokenKey), let token = String(data: data, encoding: .utf8) {
            self.userToken = token
        }
        Task { await refreshCapabilities() }
    }

    var isAuthorized: Bool { authStatus == .authorized }
    var hasCatalogPlayback: Bool { capabilities.contains(.musicCatalogPlayback) }
    var canAddToCloudLibrary: Bool { capabilities.contains(.addToCloudMusicLibrary) }

    func requestAuthorization() async {
        if #available(iOS 15.0, *) {
            let status = await SKCloudServiceController.requestAuthorization()
            authStatus = status
            if status == .authorized {
                await refreshCapabilities()
            }
        } else {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                SKCloudServiceController.requestAuthorization { [weak self] status in
                    Task { @MainActor in
                        self?.authStatus = status
                        if status == .authorized {
                            Task { await self?.refreshCapabilities() }
                        }
                        cont.resume()
                    }
                }
            }
        }
    }

    func refreshCapabilities() async {
        let controller = SKCloudServiceController()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            controller.requestCapabilities { [weak self] caps, error in
                Task { @MainActor in
                    self?.capabilities = caps
                    self?.lastError = error?.localizedDescription
                    cont.resume()
                }
            }
        }
    }

    func requestUserTokenIfPossible() async {
        guard let devToken = Bundle.main.object(forInfoDictionaryKey: "APPLE_MUSIC_DEVELOPER_TOKEN") as? String, !devToken.isEmpty else {
            lastError = "Missing APPLE_MUSIC_DEVELOPER_TOKEN in Info.plist."
            return
        }
        let controller = SKCloudServiceController()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            controller.requestUserToken(forDeveloperToken: devToken) { [weak self] token, error in
                Task { @MainActor in
                    if let token {
                        self?.userToken = token
                        try? self?.keychain.setData(Data(token.utf8), key: self?.userTokenKey ?? "appleMusic.userToken")
                        self?.lastError = nil
                    } else {
                        self?.lastError = error?.localizedDescription ?? "Failed to get Apple Music user token."
                    }
                    cont.resume()
                }
            }
        }
    }
}