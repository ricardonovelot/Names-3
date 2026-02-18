# Deep Trace: FaceEmbedding Insert Paths

## Summary

**All 5 current insert paths set `contactUUID` before insert.** No active code path creates unassigned (`contactUUID == nil`) FaceEmbeddings. If 1 GB of unassigned faces exists, it likely came from: (1) removed/legacy pre-indexing code, (2) an unfound bug, or (3) orphaned embeddings after contact deletion (those would have `contactUUID` set but point to deleted contacts—different from `nil`).

---

## Insert Path 1: PhotoDetailViewController.persistFaceEmbeddingsForSavedFaces

**File:** `Views/Photos/PhotoDetailViewController.swift:1029–1054`

**Flow:**
1. User assigns faces to contacts and saves.
2. For each `(contact, faceImage)` in `savedFaces`:
   - `FaceRecognitionService.detectFacesAndGenerateEmbeddings(in: faceImage, ...)` → returns `[FaceEmbedding]` (contactUUID nil)
   - Takes `first`, sets `first.contactUUID = contact.uuid`
   - `context.insert(first)`

**Verdict:** ✓ Always assigned before insert.

---

## Insert Path 2: WelcomeFaceNamingViewController.saveCurrentFaces

**File:** `Views/Onboarding/WelcomeFaceNamingViewController.swift:2645–2684`

**Flow:**
1. User names faces in Name Faces carousel and saves.
2. For each named face with `existingContact`:
   - `FaceEmbedding(assetIdentifier: "name-faces-\(UUID())", contactUUID: existingContact.uuid, ...)`
   - `modelContext.insert(embedding)`
3. For new contacts: creates `Contact`, no FaceEmbedding.

**Verdict:** ✓ Always assigned (contactUUID in initializer).

---

## Insert Path 3: WelcomeFaceNamingViewController.saveCurrentFacesAsync

**File:** `Views/Onboarding/WelcomeFaceNamingViewController.swift:2696–2746`

**Flow:** Same as Path 2; `FaceEmbedding(..., contactUUID: existing.uuid, ...)`.

**Verdict:** ✓ Always assigned.

---

## Insert Path 4: ManualFaceRecognitionService.insertFaceMatchResults

**File:** `Services/ManualFaceRecognitionService.swift:336–363`

**Flow:**
1. Called from `processPhotoBatch` after `processPhotoBatchOffMainActor`.
2. `processPhotoBatchOffMainActor`:
   - Runs Vision on each asset → `[FaceEmbedding]` (contactUUID nil)
   - Compares each to reference; only **matches** go into `results` (FaceMatchResult)
   - Original embeddings are never inserted
3. `insertFaceMatchResults`:
   - For each `FaceMatchResult`, creates `FaceEmbedding(..., contactUUID: contactUUID, ...)`
   - `modelContext.insert(embedding)`

**Verdict:** ✓ Only matches inserted, always with contactUUID.

---

## Insert Path 5: ManualFaceRecognitionService.getReferenceEmbedding

**File:** `Services/ManualFaceRecognitionService.swift:436–470`

**Flow:**
1. Find Similar needs a reference embedding from the contact photo.
2. `detectFacesAndGenerateEmbeddings(in: contactPhoto, ...)` → `[FaceEmbedding]` (contactUUID nil)
3. Takes `first`, sets `embedding.contactUUID = contact.uuid`
4. `modelContext.insert(embedding)`

**Verdict:** ✓ Always assigned before insert.

---

## Paths That Do NOT Insert FaceEmbedding

| Location | What it does |
|----------|---------------|
| **BulkAddFacesView** | Inserts `Contact` and `FaceBatchFace` (batch store). No FaceEmbedding. |
| **PhotoDetailView.saveAll** | Inserts `Contact` only. No FaceEmbeddings. |
| **FaceRecognitionService** | Creates FaceEmbeddings in memory; returns to caller. Never inserts. |
| **batchProcessAssets** | Dead code—never called. |
| **FaceRecognitionCoordinator** | Fetches and deletes embeddings; does not insert. |

---

## matchStoredEmbeddingsOnly: Consumer of Unassigned Embeddings

**File:** `Services/ManualFaceRecognitionService.swift:380–419`

**Flow:**
- For assets in `toMatchOnly` (already have stored faces):
  - `FaceAnalysisCache.fetchStoredEmbeddings(forAssetIdentifier: ...)` → existing embeddings
  - For each embedding with `contactUUID == nil`:
    - If it matches the reference, sets `embed.contactUUID = contactUUID`
  - Saves context

**Implication:** This logic assumes unassigned embeddings already exist. It only assigns them; it does not create them.

---

## Where Unassigned Embeddings Could Have Come From

1. **Removed pre-indexing flow** – A past version may have scanned the library and inserted all detected faces with `contactUUID == nil` for later matching. That code is not present now.
2. **Bug in an older build** – A previous bug could have inserted embeddings without setting contactUUID.
3. **Different store** – `ManualFaceRecognitionService` can create a fallback `ModelContainer` when `appContainer` is nil (line 119–122). That uses a different store; results would not sync. If that path ever inserted embeddings, they could be in a separate store, not the main one.
4. **CloudKit / sync** – Unlikely, but sync from another device with different logic could introduce unassigned embeddings.

---

## Recommendations

1. **Assert before insert:** Add a precondition that `contactUUID != nil` for any FaceEmbedding insert.
2. **Audit fallback container:** Ensure Find Similar always receives `appContainer` so no separate store is used.
3. **Storage Manager:** Use “Delete unassigned faces” to reclaim space; it is the correct way to clean up.
4. **Optional: Orphan check** – Consider detecting embeddings whose `contactUUID` points to a non-existent contact and either deleting or flagging them.
