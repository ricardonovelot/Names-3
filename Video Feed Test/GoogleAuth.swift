import Foundation
import AuthenticationServices
import UIKit

struct GoogleOAuthConfig {
    private static let placeholder = "YOUR_IOS_CLIENT_ID.apps.googleusercontent.com"

    static var clientID: String {
        if let id = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String,
           !id.isEmpty { return id }
        return placeholder
    }

    private static var redirectURIOverride: String? {
        if let r = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_REDIRECT_URI") as? String,
           !r.isEmpty { return r }
        return nil
    }

    static var scopes: [String] = [
        "openid",
        "email",
        "https://www.googleapis.com/auth/youtube.readonly"
    ]
    static var tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    static var authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!

    static var redirectScheme: String {
        if let override = redirectURIOverride,
           let scheme = URL(string: override)?.scheme,
           !scheme.isEmpty {
            return scheme
        }
        let base = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(base)"
    }

    static var redirectURI: String {
        if let override = redirectURIOverride { return override }
        return "\(redirectScheme):/oauthredirect"
    }

    static var isConfigured: Bool {
        clientID != placeholder
    }
}

struct GoogleTokens: Codable {
    var accessToken: String
    var expiresAt: Date
    var refreshToken: String?

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }
}

actor GoogleAuth {
    static let shared = GoogleAuth()

    private let keychain = KeychainStore(service: "VideoFeedTest.Google")
    private let tokenKey = "google.tokens"

    private var tokens: GoogleTokens?

    @MainActor private static var currentSession: ASWebAuthenticationSession?
    @MainActor private static let sharedPresenter = WebAuthPresenter()

    var isReady: Bool {
        GoogleOAuthConfig.isConfigured
    }

    func restore() async -> Bool {
        if let data = try? keychain.getData(key: tokenKey),
           let t = try? JSONDecoder().decode(GoogleTokens.self, from: data) {
            Diagnostics.log("GoogleAuth.restore: found tokens; expired=\(t.isExpired) hasRefresh=\(t.refreshToken != nil)")
            if t.isExpired && t.refreshToken == nil {
                Diagnostics.log("GoogleAuth.restore: tokens expired and no refresh_token; ignoring stored tokens")
                tokens = nil
                return false
            }
            tokens = t
            return true
        }
        Diagnostics.log("GoogleAuth.restore: no stored tokens")
        return false
    }

    func signIn() async throws -> Bool {
        guard isReady else {
            Diagnostics.log("GoogleAuth.signIn: not ready (missing clientID/redirect)")
            return false
        }

        let state = UUID().uuidString
        let codeVerifier = Self.randomString(64)
        let codeChallenge = Self.base64url(Data(Self.sha256(codeVerifier)))

        var comps = URLComponents(url: GoogleOAuthConfig.authURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: GoogleOAuthConfig.clientID),
            .init(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: GoogleOAuthConfig.scopes.joined(separator: " ")),
            .init(name: "access_type", value: "offline"),
            .init(name: "include_granted_scopes", value: "true"),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "consent")
        ]

        let callbackScheme = GoogleOAuthConfig.redirectScheme

        let url = comps.url!
        Diagnostics.log("GoogleAuth.signIn: starting ASWebAuthenticationSession; redirect=\(GoogleOAuthConfig.redirectURI)")
        let (callbackURL, returnedState) = try await Self.startWebAuth(url: url, callbackScheme: callbackScheme)
        Diagnostics.log("GoogleAuth.signIn: got callbackURL")
        guard returnedState == state else {
            Diagnostics.log("GoogleAuth.signIn: state mismatch")
            throw NSError(domain: "GoogleAuth", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid state"])
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            Diagnostics.log("GoogleAuth.signIn: missing code in callback")
            throw NSError(domain: "GoogleAuth", code: -11, userInfo: [NSLocalizedDescriptionKey: "Missing code"])
        }

        let newTokens = try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)
        Diagnostics.log("GoogleAuth.signIn: token exchange ok; hasRefresh=\(newTokens.refreshToken != nil)")
        tokens = newTokens
        try persist(tokens: newTokens)
        return true
    }

    func signOut() async {
        Diagnostics.log("GoogleAuth.signOut: clearing tokens")
        tokens = nil
        try? keychain.delete(key: tokenKey)
    }

    func validAccessToken() async throws -> String {
        if let t = tokens {
            Diagnostics.log("GoogleAuth.validAccessToken: have tokens; expired=\(t.isExpired) hasRefresh=\(t.refreshToken != nil)")
        } else {
            Diagnostics.log("GoogleAuth.validAccessToken: no tokens loaded")
        }

        if let t = tokens, !t.isExpired {
            return t.accessToken
        }
        if let refreshed = try await refreshTokensIfNeeded() {
            return refreshed.accessToken
        }
        Diagnostics.log("GoogleAuth.validAccessToken: not signed in (no token / no refresh)")
        throw NSError(domain: "GoogleAuth", code: -20, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
    }

    // MARK: - Internals

    private func refreshTokensIfNeeded() async throws -> GoogleTokens? {
        guard var t = tokens else {
            Diagnostics.log("GoogleAuth.refresh: no tokens to refresh")
            return nil
        }
        guard t.isExpired, let refresh = t.refreshToken else {
            Diagnostics.log("GoogleAuth.refresh: not needed or no refresh token")
            return nil
        }

        Diagnostics.log("GoogleAuth.refresh: attempting refresh_token grant")
        var req = URLRequest(url: GoogleOAuthConfig.tokenURL)
        req.httpMethod = "POST"
        let body: [String: String] = [
            "client_id": GoogleOAuthConfig.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh
        ]
        req.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            Diagnostics.log("GoogleAuth.refresh: failed status=\(status) body=\(text)")
            throw NSError(domain: "GoogleAuth", code: -22, userInfo: [NSLocalizedDescriptionKey: "Refresh failed"])
        }
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = payload?["access_token"] as? String,
              let expires = payload?["expires_in"] as? Double else {
            Diagnostics.log("GoogleAuth.refresh: bad payload")
            throw NSError(domain: "GoogleAuth", code: -23, userInfo: [NSLocalizedDescriptionKey: "Bad token response"])
        }
        t.accessToken = access
        t.expiresAt = Date().addingTimeInterval(expires)
        tokens = t
        try persist(tokens: t)
        Diagnostics.log("GoogleAuth.refresh: success; new expiry set")
        return t
    }

    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> GoogleTokens {
        var req = URLRequest(url: GoogleOAuthConfig.tokenURL)
        req.httpMethod = "POST"
        let body: [String: String] = [
            "client_id": GoogleOAuthConfig.clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleOAuthConfig.redirectURI
        ]
        req.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            Diagnostics.log("GoogleAuth.exchange: token exchange failed status=\(status) body=\(text)")
            throw NSError(domain: "GoogleAuth", code: -12, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed"])
        }
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = payload?["access_token"] as? String,
              let expires = payload?["expires_in"] as? Double else {
            Diagnostics.log("GoogleAuth.exchange: invalid payload")
            throw NSError(domain: "GoogleAuth", code: -13, userInfo: [NSLocalizedDescriptionKey: "Invalid token payload"])
        }

        let preservedRefresh = (payload?["refresh_token"] as? String) ?? self.tokens?.refreshToken
        Diagnostics.log("GoogleAuth.exchange: hasRefresh=\(preservedRefresh != nil)")

        return GoogleTokens(
            accessToken: access,
            expiresAt: Date().addingTimeInterval(expires),
            refreshToken: preservedRefresh
        )
    }

    private func persist(tokens: GoogleTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try keychain.setData(data, key: tokenKey)
    }

    @MainActor
    private static func startWebAuth(url: URL, callbackScheme: String) async throws -> (URL, String) {
        Diagnostics.log("GoogleAuth.webAuth: launching session")
        return try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                // Release session when finished
                Self.currentSession = nil
                if let error {
                    Diagnostics.log("GoogleAuth.webAuth: error=\(error.localizedDescription)")
                    return cont.resume(throwing: error)
                }
                guard let callback else {
                    Diagnostics.log("GoogleAuth.webAuth: no callback URL")
                    return cont.resume(throwing: NSError(domain: "GoogleAuth", code: -9, userInfo: [NSLocalizedDescriptionKey: "No callback URL"]))
                }
                let state = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "state" })?.value ?? ""
                Diagnostics.log("GoogleAuth.webAuth: callback received")
                cont.resume(returning: (callback, state))
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = Self.sharedPresenter

            let started = session.start()
            Diagnostics.log("GoogleAuth.webAuth: session.start()=\(started)")
            if started {
                Self.currentSession = session
            } else {
                cont.resume(throwing: NSError(domain: "GoogleAuth", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to start web auth session"]))
            }
        }
    }

    private final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }

    private static func randomString(_ len: Int) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var s = ""
        s.reserveCapacity(len)
        for _ in 0..<len { s.append(chars.randomElement()!) }
        return s
    }

    private static func sha256(_ str: String) -> Data {
        let data = Data(str.utf8)
        return data.sha256()
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Data {
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(self.count), &hash)
        }
        return Data(hash)
    }
}

import CommonCrypto