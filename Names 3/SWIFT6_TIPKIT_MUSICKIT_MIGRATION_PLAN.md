# Swift 6 / TipKit / MusicKit Migration Plan

## 1. TipKit TipEvents (Swift 6 MainActor isolation)

### Root cause
TipKit's `#Rule` macro generates code in a **nonisolated** context. When it references `TipEvents.contactCreated`, the compiler sees `Tips.Event` as MainActor-isolated (from TipKit framework), causing: *"Main actor-isolated static property can not be referenced from a nonisolated context"*.

### Fix applied
- **TipEvents.swift**: Use `nonisolated static let` (per compiler: `nonisolated(unsafe)` is unnecessary for Sendable `Tips.Event`)
- **TipEvents.swift**: Keep `@preconcurrency import TipKit` to relax concurrency checks for TipKit types
- **Build settings**: `SWIFT_STRICT_CONCURRENCY = minimal` (already set)

### If errors persist
1. **Option A**: File feedback with Apple (FB) — TipKit's `#Rule` macro should generate MainActor-isolated code or accept nonisolated Event references
2. **Option B**: Per-file override — Add `-Xfrontend -strict-concurrency=minimal` for Tips/*.swift only (Xcode: Build Phases → Compile Sources → add flag for specific files)
3. **Option C**: Temporarily remove rules that use Events — Tips still work, just without event-based display logic

---

## 2. AppleMusicAuth (StoreKit → MusicKit, iOS 18+)

### Deprecations (iOS 18.0)
| Old (StoreKit) | New (MusicKit) |
|----------------|----------------|
| `SKCloudServiceAuthorizationStatus` | `MusicAuthorization.Status` |
| `SKCloudServiceController.authorizationStatus()` | `MusicAuthorization.currentStatus` |
| `SKCloudServiceController.requestAuthorization()` | `MusicAuthorization.request()` |
| `SKCloudServiceCapability` | `MusicSubscription` |
| `requestCapabilities(completionHandler:)` | `MusicSubscription.current` |
| `requestUserToken(forDeveloperToken:completionHandler:)` | MusicKit handles tokens via `MusicDataRequest` / App Service |

### Migration approach
1. Add `import MusicKit`
2. Use `#available(iOS 18.0, *)` for MusicKit path; keep StoreKit fallback for older iOS if deployment target allows
3. Map `MusicAuthorization.Status` ↔ `SKCloudServiceAuthorizationStatus` for `@Published` compatibility
4. Replace capabilities with `MusicSubscription.current` → `canPlayCatalogContent`, `canAddToCloudMusicLibrary`, etc.
5. **User token**: MusicKit manages tokens internally for `MusicDataRequest`. If custom API calls need a user token, use `MusicKit`'s token provider or keep StoreKit path for that specific call until MusicKit exposes it.

### Deployment target
Project uses `IPHONEOS_DEPLOYMENT_TARGET = 18.0` — can use MusicKit exclusively, no StoreKit fallback needed.

### Migration completed
- **AppleMusicAuth.swift**: Migrated to MusicKit. Uses `MusicAuthorization.request()`, `MusicAuthorization.currentStatus`, `MusicSubscription.current`. Removed StoreKit imports. `requestUserTokenIfPossible()` retained for API compatibility; MusicKit manages tokens for standard catalog operations.
