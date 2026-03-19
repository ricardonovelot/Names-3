# Names 3 — Agent Orientation Guide

Names 3 is a production iOS app that helps users name the faces in their photo library and practice recognizing them through quizzes and a TikTok-style media feed.

---

## Coding Standards (Read First)

Before making any changes, read the agent guides inside `Names 3/`:

| Guide | Covers |
|---|---|
| [`Names 3/Agent General.md`](Names%203/Agent%20General.md) | Role persona, core principles, build-proofing guardrails, concurrency rules, output format |
| [`Names 3/Agent guide for SwiftUI.md`](Names%203/Agent%20guide%20for%20SwiftUI.md) | SwiftUI patterns, `@Observable`, state management, navigation |
| [`Names 3/Agent guide for UIKit.md`](Names%203/Agent%20guide%20for%20UIKit.md) | UIKit patterns, diffable data sources, collection layouts, UIKit↔SwiftUI bridges |

---

## Tech Stack

- **Language:** Swift 6.2+, strict concurrency, `async/await` throughout
- **UI:** SwiftUI + UIKit hybrid — SwiftUI for composition and simple views, UIKit (`UICollectionView`, `UIViewController`) for performance-critical screens
- **Data:** SwiftData (primary store) + CloudKit private database (`iCloud.com.ricardo.Names4`)
- **Media:** PHPhotoLibrary, AVFoundation, Vision (face detection), CoreML (face embeddings)
- **Music:** MusicKit / Apple Music integration (in `Video Feed Test/`, partially experimental)
- **Tips:** TipKit with a local-only store
- **Minimum deployment:** iOS 18+; some features guarded with `@available(iOS 26, *)`

---

## Directory Map

```
Names-3/
├── AGENTS.md                        ← you are here
├── KNOWN_CONSOLE_MESSAGES.md        ← catalog of benign runtime console noise
│
├── Names 3/                         ← all Swift source
│   ├── Agent General.md             ← coding standards (read before editing)
│   ├── Agent guide for SwiftUI.md   ← SwiftUI standards
│   ├── Agent guide for UIKit.md     ← UIKit standards
│   ├── Agent Instructions.md        ← brief UIKit reminder
│   │
│   ├── App/                         ← @main entry + AppDelegate
│   ├── Extensions/                  ← SwiftUI + UIKit extensions
│   ├── Model+Preview+Sample/        ← SwiftData model definitions + Xcode Preview helpers
│   ├── Models/                      ← Non-persisted models (PhotoGroup, QuizSession)
│   ├── Resources/                   ← Localizable.strings (Base + es-MX)
│   │
│   ├── Services/                    ← Business logic, coordinators, background workers
│   │   ├── Photos/                  ← PHPhotoLibrary, image cache, photo grouping
│   │   └── PhotoCarousel/           ← Photo carousel loading architecture
│   │       └── Drivers/             ← ⚠️ EXPERIMENTAL: PhotoArch1–5 (5 variants, none default)
│   │
│   ├── Tips/                        ← TipKit tip definitions per screen
│   ├── Utilities/                   ← Haptics, keyboard, launch profiling, image utils
│   │
│   ├── Video Feed Test/             ← ⚠️ EXPERIMENTAL: TikTok-style feed + Apple Music (~90 files)
│   │                                    Not a clean module; treat as in-progress R&D
│   │
│   ├── ViewModels/                  ← ContentViewModel (root @Observable view model)
│   │
│   └── Views/
│       ├── Albums/                  ← Albums tab (newly added; iCloud KV-backed AlbumStore)
│       ├── Archive/                 ← Deleted items screen
│       ├── BulkFaces/               ← Bulk Vision-based face add workflow
│       ├── Components/              ← Shared reusable views (GrowingTextView, etc.)
│       ├── Contacts/                ← People / contacts feed, contact detail, photo selector
│       ├── Feed/                    ← Media feed (video + photos interleaved)
│       │   ├── Arch1–Arch5          ← ⚠️ EXPERIMENTAL: 5 alternative feed architectures
│       │   ├── Implementations/     ← FeedImpl5_StrictUnbind.swift (live; used by ALL modes)
│       │   └── PhotoCarousel/       ← Photo carousel inside feed cells
│       ├── Journal/                 ← Journal entry CRUD
│       ├── Notes/                   ← Notes feed
│       ├── Onboarding/              ← Onboarding flow (gate + face-naming wizard)
│       ├── People/                  ← People tab, unified feed
│       ├── Photos/                  ← Photos grid, pager, detail, zoom transitions
│       ├── QuickNotes/              ← Quick-input notes
│       ├── Quiz/                    ← Quiz screen, streak, note rehearsal
│       └── Settings/                ← Settings + storage manager
│
├── Names 3.xcodeproj/
└── Names 3Tests/
```

### Loose Swift files at `Names 3/` root (actively used, pending cleanup)

| File | Used by |
|---|---|
| `CropView.swift` | PhotoDetailView, ContactPhotoSelectorModifier, BulkAddFacesView |
| `SimpleCropView.swift` | PhotoDetailView, PhotoDetailViewController, ContactPhotoSelectorModifier |
| `GlassBackgroundCompat.swift` | 11+ files — foundational `liquidGlass()` modifier with iOS 26 / fallback |
| `RegexShortcutsView.swift` | SettingsView (defines `QuickInputGuideView`, filename is a misnomer) |

---

## Architecture

### App Launch Flow

```
Names_3App (@main)
  └── AppLaunchCoordinator.launch()
        ├── Phase 1a (sync, <1ms): ConnectivityMonitor, StorageMonitor, CloudKitResetCoordinator
        ├── Phase 1b (sync, ~5ms): TipKit config, PHPhotoLibrary observer
        ├── Phase 2 (async/detached): UUID migration, storage-shrink migration
        └── Phase 3 (sync): Onboarding edge-case gate
  └── LaunchRootView
        ├── OnboardingGateView   (first launch)
        └── ContentView          (returning user)
              └── MainTabView    (tab bar: People, Photos, Albums, Practice, Journal, Settings)
```

### UI Pattern (Hybrid SwiftUI + UIKit)

Most views are SwiftUI. Performance-critical screens are UIKit wrapped via `UIViewControllerRepresentable`:

| UIKit screen | Why UIKit |
|---|---|
| `PhotosGridViewController` | UICollectionView, custom zoom transition |
| `TikTokFeedViewController` | Vertical paging video feed, AVPlayer management |
| `WelcomeFaceNamingViewController` | Face carousel + naming (~4k lines, God object) |
| `ContactsFeedViewController` | Large diffable list |
| `UnifiedPeopleFeedViewController` | Large diffable list |
| `AlbumsProfileViewController` | Instagram-style grid, diffable |

### State Management

- **Root state:** `ContentViewModel` — `@Observable @MainActor`, holds selected tab, people filter, async contact loads
- **View-local state:** `@State`, `@Binding`
- **Persisted state:** `@Query` (SwiftData) in views, `@AppStorage` for simple preferences
- **Cross-view singletons:** `AlbumStore.shared` (Combine), `ImageCacheService`, `FaceAnalysisCache`

### Data Layer

**Primary SwiftData store** (CloudKit-mirrored):
`Contact`, `FaceEmbedding`, `QuickNote`, `JournalEntry`, `NoteRehearsalPerformance`, `QuizPerformance`, `QuizSession`, `DeletedPhoto`

**Batch SwiftData store** (`BatchModelContainer`, no CloudKit):
`FaceBatch`, `FaceBatchFace` — used for background Vision processing

Schema migrations: V1 → V2 → V3 → V4 lightweight migrations in `MigrationPlan.swift`

---

## Known Experimental / Do-Not-Rely-On Zones

These areas contain working but non-default code kept for A/B comparison or active R&D. Do not treat them as the canonical implementation.

| Area | Files | Default? |
|---|---|---|
| Feed architectures | `Views/Feed/Arch1_ReactivePipelineFeed.swift` … `Arch5_AheadOfTimeFeed.swift` | No — `.original` (`TikTokFeedViewController`) is default |
| Photo carousel drivers | `Services/PhotoCarousel/Drivers/PhotoArch1_*.swift` … `PhotoArch5_*.swift` | No — `PhotoCarouselImageService.swift` is default |
| Video Feed Test module | `Video Feed Test/` (~90 files) | Partially — `TikTokFeedViewModel`, `SingleAssetPlayer`, etc. are active; Apple Music and sharing code is in-progress R&D |

`FeedImpl5_StrictUnbind.swift` inside `Views/Feed/Implementations/` is **live production code** (used by `FeedCellBuilder` for all architectures including the default) despite its "5" naming.

---

## Key Conventions

- **No stored properties in extensions.** Computed properties and methods only.
- **Newest-first ordering** for all feeds and lists unless explicitly overridden.
- **`@MainActor` only when necessary** — default to actor isolation via `FeedLoadActor`, `BatchModelContainer`, etc.
- **`.sheet(item:)`** over `.sheet(isPresented:) + separate state` for data-driven sheets.
- **Single loading state per screen** — no duplicate spinners in host + child.
- **`liquidGlass(in:)`** (from `GlassBackgroundCompat.swift`) for all glass backgrounds — never call `glassEffect()` directly at call sites.
- **Wrap iOS 26+ APIs** in `@available(iOS 26, *)` with a visual fallback.
