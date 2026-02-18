# App storage usage: root cause and fixes

This document explains why the app can use a large amount of device storage (e.g. ~2.86 GB for ~50 contacts) and what we changed to reduce it without slowing the Name Faces experience.

## Root cause

1. **Contact.photo and FaceEmbedding.thumbnailData stored at full size/quality**
   - We were persisting face crops as JPEG with **no max dimension** and **high quality (0.92 or 1.0)**. A single crop at 1024×1024 or larger at 0.92 can be 500 KB–2 MB.
   - **Contact.photo** was set from the same full-size crop in Name Faces, Photo Detail, ContentView, ContactDetailsView, and BulkAddFacesView.
   - **FaceEmbedding.thumbnailData** was set at 0.92 (or 0.8 in FaceRecognitionService) with no downscaling. Each “Find Similar” and each Name Faces save adds embeddings; with many faces, thumbnail data alone can be hundreds of MB.

2. **No single policy for “storage-sized” images**
   - Downscaling existed only in one place (BulkAddFacesView, max 2400 pt). Everywhere else we used `image.jpegData(compressionQuality: 0.92)` (or 1.0 in ContactDetailsView), so the SwiftData store grew with full-resolution blobs.

3. **What counts toward the 2.86 GB**
   - SwiftData store (Contact.photo, FaceEmbedding.thumbnailData/embeddingData, and the rest of the model).
   - Core Data / SQLite WAL and checkpoints.
   - Possibly system caches attributed to the app (e.g. Photos framework thumbnails). We can’t control that; we can only reduce what we persist.

## Fixes (no slowdown to Name Faces)

We did **not** change what we load or pre-cache in the Name Faces view (carousel, display size, cache window). We only changed **what we write** to the store.

### 1. Centralized stored-photo sizing (`ImageProcessing.swift`)

- **`jpegDataForStoredContactPhoto(_ image: UIImage) -> Data`**  
  Use for **Contact.photo** everywhere. Downscales to **640 pt** max dimension, JPEG quality **0.85**. Keeps avatars sharp in list and detail while avoiding multi‑MB blobs.

- **`jpegDataForStoredFaceThumbnail(_ image: UIImage) -> Data`**  
  Use for **FaceEmbedding.thumbnailData** (and any other small face thumbnail we persist). Downscales to **320 pt** max dimension, JPEG quality **0.8**.

- **`downscaleJPEG(data:maxDimension:quality:)`**  
  Still available for existing call sites that work with `Data` (e.g. BulkAddFacesView’s existing flow if needed).

### 2. Where we use the helpers

| Location | What changed |
|----------|----------------|
| **WelcomeFaceNamingViewController** | New contacts: `photo = jpegDataForStoredContactPhoto(faceInfo.image)`. New embeddings: `thumbnailData = jpegDataForStoredFaceThumbnail(faceInfo.image)`. Same for batch-save path. |
| **PhotoDetailViewController** | All assignments to `contact.photo` use `jpegDataForStoredContactPhoto(faceImage)`. |
| **PhotoDetailView** | Same for contact.photo and for contact creation in save flow. |
| **ContentView** | Contact.photo set from face image uses `jpegDataForStoredContactPhoto(faceImage)`. |
| **ContactDetailsView** | Replaced `croppedImage.jpegData(compressionQuality: 1.0)` with `jpegDataForStoredContactPhoto(croppedImage)`. |
| **BulkAddFacesView** | FaceBatchFace thumbnails: `jpegDataForStoredFaceThumbnail(fe.image)`. Contact.photo on export: `jpegDataForStoredContactPhoto(face.image)`. |
| **FaceRecognitionService** | `thumbnailData = jpegDataForStoredFaceThumbnail(faceCrop)` when creating FaceEmbedding from a crop. |

### 3. Expected effect

- **Contact.photo:** Each stored photo is now at most ~640×640 at 0.85 quality instead of full crop size at 0.92/1.0. Typical size drops from hundreds of KB (or more) to tens of KB per contact.
- **FaceEmbedding.thumbnailData:** Each thumbnail is at most ~320×320 at 0.8. Large per-embedding sizes are reduced proportionally.
- **Existing data:** Already-saved contacts and embeddings are unchanged until the user updates that contact’s photo or we run a one-off migration. New and updated saves use the new sizes. Over time, storage should grow much more slowly and stay lower for the same number of contacts/faces.

### 4. What we did not change

- **Name Faces loading/display:** Still uses full-resolution assets and the same display size (1024/1440) and cache window. No change to perceived speed or quality on screen.
- **ImageCacheService:** Memory-only (NSCache); no disk cache there.
- **PHCachingImageManager:** System-managed; we didn’t add or remove caching.

## Optional follow-ups

- **Migration:** Add a one-time pass (e.g. in MigrationPlan or a separate coordinator) that rewrites existing `Contact.photo` and `FaceEmbedding.thumbnailData` through the new helpers to shrink the store for existing users.
- **Monitoring:** If you need to attribute the 2.86 GB precisely, inspect the app’s Application Support and Caches directories (e.g. SwiftData store file and WAL size) and compare before/after the fix over time.
- **Save failure on ENOSPC:** See `STORAGE_IMPACT_ANALYSIS.md` for handling “no space left” when saving (e.g. surface a “free up storage” message).
