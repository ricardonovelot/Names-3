# Impact of No / Low Device Storage

This document summarizes how the app behaves when the device runs out of storage (or is very low) and what we do to inform the user.

## How “no storage” affects the app

### 1. **SwiftData / Core Data persistence**

- **Local saves:** `ModelContext.save()` can fail with `NSPOSIXErrorDomain` and code **28 (ENOSPC)** — “No space left on device.” SwiftData uses a local SQLite store; when the volume is full, writes fail.
- **Impact:** New or updated contacts, notes, tags, face embeddings, and quiz state may not persist. The app can appear to save (no immediate throw if autosave is deferred) but the next launch or fetch may not show the change. In the worst case, the store can become inconsistent if only part of a transaction is written.
- **Where we save:** ContentView (contact moves, quick input), ContactDetailsView, PhotoDetailViewController (face assignments), QuizViewModel, QuickInputView, TagPickerView, WelcomeFaceNamingViewController, ManualFaceRecognitionService, and others. All of these call `modelContext.save()` or `context.save()` and can hit ENOSPC.

### 2. **CloudKit sync**

- **Under the hood:** SwiftData with CloudKit uses `NSPersistentCloudKitContainer`, which writes to a local mirror and then syncs to iCloud. If the **device** has no free space:
  - The local mirror cannot be updated (same ENOSPC on SQLite/WAL).
  - Sync to CloudKit may stall or fail because the container can’t write pending changes or history.
- **iCloud quota:** If the **iCloud account** is over quota (`CKError.quotaExceeded`), sync also fails. That is separate from device storage; we currently focus on device storage for the “phone storage full” message.
- **Impact:** Data added on this device may never reach iCloud; changes from other devices may not download. The user may see an empty or stale list even with Wi‑Fi and iCloud enabled.

### 3. **Photos and image handling**

- **Photo Library:** Reading from the Photo Library usually still works when storage is low; the system can return already-downloaded assets. Saving new photos or exporting can fail with ENOSPC.
- **Image caches:** `ImageCacheService`, `FaceThumbnailPreheater`, and in-memory or disk caches may fail to write. The app may fall back to decoding on demand or show placeholders. No crash expected, but slower or missing thumbnails.
- **Name Faces / face crops:** Saving contact photos (e.g. face crops) goes through SwiftData (Contact.photo) and/or local files. Both can fail with no space.

### 4. **Batch and other stores**

- **BatchModelContainer** (FaceBatch, FaceBatchFace) is a second persistent store. It is subject to the same volume; if the device is full, batch operations may not persist.

### 5. **User-visible symptoms**

- Feed stays empty or doesn’t update after adding people (saves or sync failing).
- “Find Similar Faces” or face assignments don’t stick (writes to SwiftData/store fail).
- Quiz progress or new notes don’t save.
- App doesn’t crash, but actions appear to do nothing or data “disappears” after restart.

## What we do in the app

### StorageMonitor

- **StorageMonitor** (see `Services/StorageMonitor.swift`) checks **device** free space using `volumeAvailableCapacityForImportantUsageKey` (space available for “important” use, including purgeable caches).
- **Threshold:** We treat the device as “low on storage” when this value is below **50 MB**, so we show the message before the user hits absolute zero.
- **When we check:** At launch (Phase 1 in AppLaunchCoordinator) and when the app becomes active (scene phase `.active`), so after the user frees space we can clear the message.

### Message in the feed

- When the **feed is empty**, we show one of:
  - **“Syncing…”** — during mirroring reset or initial sync window.
  - **“Not syncing — storage full”** — when `StorageMonitor.shared.isLowOnDeviceStorage` is true. We explain that the user should free space so the list can sync with iCloud and point them to **Settings → General → iPhone Storage** (or iPad Storage on iPad if you add a variant).
- This is shown in the same empty-state area as “No people yet” and the iCloud hint, so the user gets a clear reason why sync might not be working.

### What we don’t do (yet)

- **iCloud quota:** We don’t yet detect or show a specific message for iCloud quota exceeded. That would require observing `NSPersistentCloudKitContainer` events or CloudKit errors and surfacing a different string (e.g. “iCloud storage full”).
- **Save failure handling:** We don’t globally catch `modelContext.save()` failures and map ENOSPC to a banner or alert. Many call sites use `try?` or don’t surface the error. A future improvement is to centralize save error handling and show “Couldn’t save — free up space” when the error is ENOSPC.
- **Settings:** We don’t show storage status in Settings yet; the message is only in the feed empty state when the list is empty.

## Recommendations

1. **Keep the 50 MB threshold** unless you have data that shows a different value is better (e.g. SwiftData needs more headroom on your devices).
2. **Consider a global “low storage” banner** (like the offline banner) when `isLowOnDeviceStorage` is true and the user is adding/editing data, so they see the warning even when the feed isn’t empty.
3. **Consider surfacing save failures:** When a save throws and the error is ENOSPC, show a short alert or toast: “Not enough space to save. Free up storage in Settings.”
4. **Optional:** Add an “iCloud storage full” path (e.g. from CloudKit error observation) and a separate string so users can distinguish device vs iCloud.
