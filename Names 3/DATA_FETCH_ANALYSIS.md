# Data Fetch Analysis & Optimizations

This document summarizes the deep dive on data fetching that was causing extremely long waits, and the limits/patterns applied so the app stays responsive.

## Root causes of long waits

1. **Unbounded SwiftData fetches** – Several code paths fetched *all* rows (no `fetchLimit` or predicate), so with CloudKit sync and large datasets the main thread could block for a long time.
2. **Unbounded photo library loads** – When scope was "all" or Phase 2 "remaining photos", the app loaded the entire library into memory (enumerate + group), which can be 50k+ assets.
3. **Fetching all contacts when only a few were needed** – e.g. photo detail only needs contacts for the faces in that photo; quiz resume only needs contacts in the current session.

## Changes made

### SwiftData / ModelContext

| Location | Before | After |
|----------|--------|--------|
| **PhotoDetailViewController** (photo detail onAppear) | `FetchDescriptor<Contact>()` → all contacts | Fetch only contacts whose `uuid` is in the face embeddings’ `contactUUID` set (predicate + small fetch). |
| **QuizViewModel.resumeSession()** | `FetchDescriptor<Contact>()` → all contacts | Fetch only contacts whose `uuid` is in `session.contactIDs` (predicate + `fetchLimit`). |
| **FaceAnalysisCache.fetchAssetIdentifiersWithStoredFaces** | `FetchDescriptor<FaceEmbedding>()` → all rows | Added `fetchLimit = 50_000` and `sortBy` so the fetch is bounded and deterministic. |
| **FaceAnalysisCache.assetIdentifiersWithStoredFaces(from assets:)** | Fetched all `FaceEmbedding`, then filtered by asset IDs | Single fetch with predicate `assetIdentifier in ids` so only relevant rows are loaded. |
| **WelcomeFaceNamingViewController.fetchContacts()** | All non-archived contacts | `fetchLimit = 500`, `sortBy: [SortDescriptor(\.name)]` for name suggestions. |

### Photo library

| Location | Before | After |
|----------|--------|--------|
| **PhotosGridViewController Phase 2** | `fetchAssets(..., fetchLimit: 0)` → entire library | `fetchLimit: maxTotalAssetsInGrid` (5000). Phase 2 loads up to 5000 most recent instead of unbounded. |
| **PhotosPickerViewModel.loadAllAssets()** | Enumerated entire `PHFetchResult` for scope `.all` | Enumerate only up to `maxAssetsWhenLoadingAll` (5000) then stop. |

### Already bounded (unchanged)

- **ContentView** `@Query`: already uses `fetchLimit = 2000` for contacts.
- **PhotosGridViewController Phase 1**: 300 assets then show UI.
- **PhotosInlineView**: `recentPhotosLimit = 300`.
- **UUIDMigrationService**: uses `fetchLimit = 1` for empty check; full migration runs in background.

## Constants to tune

- `FaceAnalysisCache.maxAssetIdentifiersFetchLimit` = 50_000  
- `PhotosGridViewController.maxTotalAssetsInGrid` = 5000  
- `PhotosPickerViewModel.maxAssetsWhenLoadingAll` = 5000  
- `WelcomeFaceNamingViewController.contactsFetchLimitForSuggestions` = 500  

Increase these only if you have a clear use case and have measured that the platform can handle the extra load without hurting responsiveness.

## Recommendations

1. **New fetches** – Prefer a predicate that matches only the IDs you need; add `fetchLimit` (and optionally `sortBy`) for any "all" or open-ended query.
2. **Photo library** – Avoid loading the full library into a single array; use `PHFetchResult` with a limit or paginate (e.g. by date range or index).
3. **@Query** – Keep a reasonable `fetchLimit`; remember SwiftData re-evaluates when the store changes (e.g. CloudKit sync), so large limits can mean repeated heavy work during sync.
4. **FaceEmbedding / FaceCluster** – These can grow large; any "fetch all" should be capped or replaced with predicate + limit.
