# Known Console Messages

These messages appear in the Xcode console during development. They originate from system frameworks or known SwiftUI behavior and do not indicate app bugs.

**Verbose logging:** Default verbosity is `.off` in DEBUG to reduce yellow console noise. To re-enable launch, feed, video, and coordinator logs: set the `VF_LOG` environment variable (e.g. `VF_LOG=compact` or `VF_LOG=verbose`) in the scheme's Run → Arguments → Environment Variables.

| Message | Source | Notes |
|---------|--------|-------|
| `Update NavigationRequestObserver tried to update multiple times per frame` | SwiftUI | Mitigated by deferring `NavigationPath` updates to the next run loop in `ContentView` (tab switching, quick input). |
| `<<<< FigApplicationStateMonitor >>>> signalled err=-19431` | AVFoundation | Benign system log from Apple's media framework during playback state transitions. |
| `<<<< FIGSANDBOX >>>> signalled err=-17507` | AVFoundation | Known with iCloud/streaming video. We use `.automatic` delivery mode to minimize; may still appear when AVPlayer loads assets. |
| `Error returned from daemon: Error Domain=com.apple.accounts Code=7` | System | Mitigated: TipKit uses local-only datastore (`.url`); PhotoLibrary observer deferred until firstFrame+appActive. May still appear from SwiftData/CloudKit at ModelContainer init. |
| `<<<< FigFilePlayer >>>> signalled err=-12860` | AVFoundation | Internal FigFilePlayer diagnostic during decode/validation. **Mitigated:** (1) `SingleAssetPlayer.scheduleStallRecovery()` seeks to kick decoder on stall; (2) `PlayerItemPrefetcher` and `PlayerItemBootstrapper` limit concurrent `requestPlayerItem` calls (3 on Simulator, 4 on device) to reduce burst. Triggered by Simulator missing DetachedSignatures. |
| `cannot add handler to 4 from 1 - dropping` / `cannot add handler to 3 from 1 - dropping` | System | RunLoop handler registration failure during layout/resize. **Mitigated:** Replaced deprecated `NavigationView` with `NavigationStack` in VideoFeedSettingsView, AppleMusicSearchScreen, ContactDetailsView (note date picker sheet). May still appear with LazyVGrid, TextEditor, or Catalyst. |
| `ViewBridge to RemoteViewService Terminated Code=18` | System | Apple-labelled benign ("benign unless unexpected"); originates from TipKit or system UI widget teardown. |
| `CLIENT: Failure to determine if this machine is in the process of shutting down, err=1` | System | System daemon check at launch; entirely outside app process. |
| `LSPrefs: could not find untranslocated node for <FSNode...> Operation not permitted` | System | Gatekeeper quarantine artifact when running a dev build from a translocated path. **Mitigated:** Run Script build phase removes `com.apple.quarantine` from the app bundle to prevent App Translocation. If it still appears: use Xcode's default DerivedData location (Preferences → Locations), or move the project out of Downloads. Proceeds on assumption app is not translocated. |
| `Unable to obtain a task name port right for pid N: (os/kern) failure (0x5)` | System | Sandbox restriction in simulator; process cannot inspect other processes. Benign. |
| `os_unix.c:51043: open(/private/var/db/DetachedSignatures) - No such file or directory` | SQLite/Security | System code-signature DB path. Simulator lacks `/private/var/db/`; SQLite open fails (errno 2). No app fix; Apple DTS: expected, benign. |
| `<<<< VRP >>>> signalled err=-12852` | AVFoundation | Internal video resource path (VRP) diagnostic during playback init. CoreMediaErrorDomain -12852; no public API to suppress. Playback proceeds normally. |
| `AddInstanceForFactory: No factory registered for id <CFUUID...> F8BB1C28-BAE8-11D6-9C31` | System | Core Audio plugin lookup. **Mitigated:** `AVAudioSession.sharedInstance()` warmed up in `AppDelegate.didFinishLaunchingWithOptions` so the subsystem loads before video playback. May still appear on Simulator. |
| `Reporter disconnected. { function=sendMessage, reporterID=... }` | CAReportingClient | Core Audio/AVFoundation telemetry reporter. Mitigated by orderly teardown: deactivate AVAudioSession before connection drops (willResignActive, viewWillDisappear, didEnterBackground, tab switch). See TikTokFeedViewController, TikTokFeedViewModel.configureAudioSession. |
| `CoreData: debug: WAL checkpoint: Database did checkpoint` | SwiftData/CoreData | Benign SQLite WAL checkpoint log. No action. |
| `Unable to simultaneously satisfy constraints` / `ItemWrapperView.width == 0` / `IB_Trailing_Trailing` | UIKit/SwiftUI | Navigation bar toolbar item layout conflict when `ItemWrapperView` gets zero width during tab switch or conditional toolbar. **Mitigated:** `.frame(minWidth: 44, minHeight: 44)` on toolbar button labels in PeopleTabToolbar, MemoriesTabToolbar, ContentView (Journal). |

---

## Deep dive: VRP -12852, FigFilePlayer -12860, DetachedSignatures, cannot add handler

### 1. `<<<< VRP >>>> signalled err=-12852`

**What:** Internal AVFoundation component (VRP = video resource path) logs CoreMediaErrorDomain -12852 during playback initialization.

**Why:** VRP handles video resource loading, DRM paths, and decoder setup. The error is an internal diagnostic; no public API exposes it. Common on Simulator where the media stack differs from device.

**Fix:** None. Playback proceeds normally. Documented only.

---

### 2. `<<<< FigFilePlayer >>>> signalled err=-12860`

**What:** FigFilePlayer (AVPlayer’s file-based backend) logs -12860 during decode/validation, often when Simulator lacks `/private/var/db/DetachedSignatures`.

**Why:** The Security framework uses that path for code-signature checks. Simulator doesn’t provide it; internal validation fails and logs this.

**Fix:** (1) `SingleAssetPlayer.scheduleStallRecovery()` seeks to current time to kick the decoder when playback stalls. Simulator uses 800ms delay (vs 1200ms on device) for faster recovery. (2) `PlayerItemPrefetcher` and `PlayerItemBootstrapper` cap concurrent `requestPlayerItem` calls at 3 (Simulator) or 4 (device), so scrolling no longer triggers a burst of 10+ simultaneous loads—each load can emit -12860.

---

### 3. `os_unix.c:51043: open(/private/var/db/DetachedSignatures) - No such file or directory`

**What:** SQLite (used by a framework) tries to open `/private/var/db/DetachedSignatures`; the path doesn’t exist in Simulator (errno 2 = ENOENT).

**Why:** DetachedSignatures is a system DB for detached code signatures (`man codesign`). It’s created on demand on real macOS; Simulator’s filesystem doesn’t include it.

**Fix:** None. Apple DTS: expected, benign. Video playback still works.

---

### 4. `cannot add handler to 4 from 1 - dropping` / `cannot add handler to 3 from 1 - dropping`

**What:** RunLoop fails to add an event handler from one context to another; the handler is dropped. Numbers are internal source/mode IDs.

**Why:** Framework-level issue (SwiftUI/UIKit), often triggered by deprecated `NavigationView`, `LazyVGrid` layout changes, `TextEditor` updates, or Catalyst. Common on Ventura+.

**Fix:** Replaced `NavigationView` with `NavigationStack` in:
- `VideoFeedSettingsView`
- `AppleMusicSearchScreen`
- `ContactDetailsView` (note date picker sheet)

May still appear with LazyVGrid or TextEditor; treat as log noise unless UI breaks.

---

### 5. `LSPrefs: could not find untranslocated node for <FSNode...> Operation not permitted`

**What:** Launch Services (LSPrefs) tries to resolve the app bundle's "untranslocated" path—the original location before Gatekeeper's App Translocation. It fails with "Operation not permitted" (sandbox/permission) and proceeds assuming the app is not translocated.

**Why:** App Translocation (macOS Sierra+) runs quarantined apps from a randomized read-only path (e.g. `/private/var/folders/.../X/[UUID]/d/Wrapper/App.app`) instead of their original location. When the app has `com.apple.quarantine` and is launched via Launch Services (Xcode Run, Simulator), the system copies it to this path. LSPrefs then tries to resolve the original path for registration/lookup and fails in sandboxed contexts.

**Fix:** (1) Run Script build phase removes `com.apple.quarantine` from the built app bundle before install, which prevents translocation. (2) If it still appears: use Xcode's default DerivedData (Preferences → Locations); avoid building from Downloads or other quarantined locations; move the project to e.g. `~/Developer` and rebuild.
