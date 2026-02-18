# Deep Analysis: Image Assets on the Name Face View

This document describes how image assets are loaded, cached, and displayed in the **Name Faces** experience (`WelcomeFaceNamingView` / `WelcomeFaceNamingViewController`).

---

## 1. Overview: Where Images Appear

The Name Faces UI shows images in **four distinct places**:

| Location | Source | Purpose |
|----------|--------|---------|
| **Main photo area** | Full-screen photo/video frame | The large image the user names faces in |
| **Carousel strip** | Thumbnails per asset | Horizontal strip to pick another photo |
| **Face chips** | Cropped face regions from current photo | One chip per detected face, with name/checkmark |
| **Name suggestions** | Contact photo data | Thumbnail next to each autocomplete row |

Each has its own pipeline from **PHAsset** (or derived data) to **UIImage** to **UI**.

---

## 2. Entry Point: Asset List (SwiftUI Layer)

**File:** `WelcomeFaceNamingView.swift`

- **`carouselAssets: [PHAsset]?`** — The list of assets that feed the carousel. `nil` while loading.
- **Loading flow:**
  1. **Fast path:** `loadCarouselAssetsFromCache(limit:)` — Resolves cached asset IDs from UserDefaults to `[PHAsset]` if cache is valid and not invalidated.
  2. **Slow path:**  
     - `fetchInitialAssets(limit:)` — First 80 (phone) or 500 (iPad) images + videos by date so the carousel can open quickly.  
     - `fetchAllImagesAndVideos(limit:)` — Full list (cap 2k phone / 5k iPad), excluding archived IDs.  
     - Background: `fetchScreenshotIDsWithZeroFacesAsync()` removes screenshots with 0 faces from the list; result is saved via `saveCarouselCache(assetIDs:)`.
- **Image use in SwiftUI layer:** Only for the screenshot face check: `PhotoLibraryService.shared.requestImage(for:targetSize:contentMode:deliveryMode:resizeMode:)` at 512×512 (phone) or 768×768 (iPad), then Vision face count. No image is displayed in SwiftUI; all display is in the embedded `WelcomeFaceNamingViewController`.

---

## 3. Main Photo Display (Center Stage)

**File:** `WelcomeFaceNamingViewController.swift`

### 3.1 Data and UI

- **`currentPhotoData: (image: UIImage, date: Date, asset: PHAsset)?`** — Current main image, date, and asset.
- **`photoImageView: UIImageView`** — Displays the main image; `contentMode = .scaleAspectFit`, inside `photoContainerView`.
- **Videos:** For video assets, a frame is shown first; then `videoPlayer` / `videoPlayerLayer` take over (same container).

### 3.2 How the main image is chosen

**`loadPhotoAtCarouselIndex(_ index: Int)`** is the single entry point when the user selects an index (tap, restored position, or scroll).

**For video assets:**

- `loadOptimizedImage(for: asset)` → `extractVideoFrame(from: asset)` (AVAssetImageGenerator at `.zero`).
- Result is applied with `applyMainImage(_:date:asset:forCarouselIndex:)`, then `setupVideoPlayer(for:carouselIndex:)` runs after a short delay.

**For image assets:**

1. **Instant show (if cached):**  
   - `cachedDisplayImages[index]` → if present, `applyMainImage(cached, ...)` and that image is also used for face detection.
2. **Placeholder then full:**  
   - If no cached display image: optionally show `carouselThumbnails[index]` as placeholder.  
   - Then load full image with `loadOptimizedImage(for: asset)` and apply.

### 3.3 Main image loading pipeline

**`loadOptimizedImage(for asset: PHAsset) async -> UIImage?`**

- **Videos:** Returns `extractVideoFrame(from: asset)` (no cache key).
- **Images:**
  - Cache key: `CacheKeyGenerator.key(for: asset, size: mainDisplayTargetSize)`  
    - `mainDisplayTargetSize = CGSize(width: 2048, height: 2048)`.
  - If `ImageCacheService.shared.image(for: cacheKey)` exists → return it.
  - Else: `requestDisplayImageOpportunistic(for: asset)` (see below), then:
    - `ImageDecodingService.decodeForDisplay(image)` (background decode),
    - store in `ImageCacheService` and return.

**`requestDisplayImageOpportunistic(for: asset) async -> UIImage?`**

- Uses **PHImageRequestOptions** with `deliveryMode = .opportunistic`, `resizeMode = .fast`, `isNetworkAccessAllowed = true`.
- `imageManager.requestImage(for: asset, targetSize: mainDisplayTargetSize, contentMode: .aspectFit, options:)`.
- Callback may fire twice (degraded then full). Continuation is resumed only when `!isDegraded`, or after a 6s fallback with the last received image.

So the **main photo** is either:

- From **in-memory display cache** (`cachedDisplayImages[index]`),
- Or from **loadOptimizedImage** → **ImageCacheService** (by asset + 2048×2048) + optional **ImageDecodingService** decode.

---

## 4. Display Image Cache (Scroll Performance)

**Purpose:** When the user scrolls the carousel, the newly centered item should show a sharp image immediately (Apple Photos–style).

### 4.1 Sizes and windows

- **`displayImageSize`:** Phone 1024×1024, iPad 1440×1440 (points/pixels).
- **`cachedDisplayImages: [Int: UIImage]`** — Index → display-quality image for the main area.
- **`cacheWindowSize`:** 8 (phone) / 20 (iPad) items each side of center.
- **`displayCacheBuffer`:** 5 (phone) / 10 (iPad) extra indices kept outside the window for fast swipe-back.
- **`lastCachedDisplayWindow: (start, end)?`** — For calling `stopCachingImages` when the window moves.

### 4.2 Filling the display cache

**`startCachingDisplayImages(around centerIndex: Int)`**

1. **PHCachingImageManager:**  
   - `imageManager.stopCachingImages(for: toStop, targetSize: displayImageSize, ...)` for assets that left the previous window.  
   - `imageManager.startCachingImages(for: assetsToCache, targetSize: displayImageSize, contentMode: .aspectFill, options: displayImageOptions())`.
2. **In-memory cache and requests:**  
   For each index in the new window:
   - If `cachedDisplayImages[i]` already set → skip.
   - Else check **ImageCacheService** with `CacheKeyGenerator.key(for: asset, size: displayImageSize)`; if hit, set `cachedDisplayImages[i]`.
   - Else: `imageManager.requestImage(for: asset, targetSize: displayImageSize, contentMode: .aspectFill, options: displayImageOptions())`; in the callback, decode with `ImageDecodingService.decodeForDisplay`, store in `ImageCacheService` and `cachedDisplayImages[i]`.
3. **Eviction:**  
   - Remove from `cachedDisplayImages` indices outside `[start - displayCacheBuffer, end + displayCacheBuffer]`.  
   - Set `carouselThumbnails[i] = nil` for indices outside a thumb margin (30 phone / 50 iPad) to limit memory.
4. **Carousel strip preheat:** Calls `startCachingCarouselThumbnails(around: centerIndex)`.

**`displayImageOptions()`:** `deliveryMode = .opportunistic`, `resizeMode = .fast`, network allowed, async.

### 4.3 When the main area shows the cached image

- **On scroll:** In `scrollViewDidScroll`, when the centered index changes, if `cachedDisplayImages[centeredIndex]` exists, `applyMainImage(cachedImage, ...)` is called immediately.
- **On restored position:** In `scrollToSavedPosition()`, the same check applies for the restored index.
- **After load:** `loadPhotoAtCarouselIndex` prefers `cachedDisplayImages[index]` for the main image and for face detection when available.

So the **main photo** is either from this **display cache** (by index) or from the **full 2048** path via `loadOptimizedImage` + **ImageCacheService**.

---

## 5. Carousel Strip Thumbnails

**Purpose:** The horizontal strip of small thumbnails; each cell shows a thumbnail or a spinner until loaded.

### 5.1 Storage and loading

- **`carouselThumbnails: [UIImage?]`** — One slot per carousel index; `nil` until loaded.
- **`thumbnailLoadingTasks: [Int: Task<Void, Never>]`** — Per-index load task so loads can be cancelled (e.g. on prefetch cancel or memory warning).
- **`carouselThumbnailSize = CGSize(width: 150, height: 150)`** — Used for both PH requests and cache key.

### 5.2 Load paths

**`loadThumbnailAtIndex(_ index: Int)`**

- Guard: index valid and `carouselThumbnails[index] == nil`.
- Cancel any existing `thumbnailLoadingTasks[index]`.
- Task: `loadThumbnailImage(for: asset)` then on main: set `carouselThumbnails[index]`, reload that cell if visible.
- Store task in `thumbnailLoadingTasks[index]`.

**`loadThumbnailImage(for asset: PHAsset) async -> UIImage?`**

- **Videos:** `loadVideoThumbnail(for: asset)` — same 150×150, `deliveryMode = .fastFormat`, no network.
- **Images:**  
  - Cache key: `CacheKeyGenerator.key(for: asset, size: carouselThumbnailSize)`.  
  - If **ImageCacheService** has it → return.  
  - Else: `requestThumbnailImage(for: asset, size: carouselThumbnailSize)` (see below), decode with **ImageDecodingService**, store in **ImageCacheService**, return.

**`requestThumbnailImage(for: asset, size:) async -> UIImage?`**

- Wraps `imageManager.requestImage(..., targetSize: size, contentMode: .aspectFill, options:)` in a continuation.
- Options: `deliveryMode = .fastFormat`, `resizeMode = .fast`, network allowed.
- Resumes on first callback that is non-degraded or has an image (so one callback).

### 5.3 PH preheat for the strip

**`startCachingCarouselThumbnails(around centerIndex: Int)`**

- **stripCacheWindowSize:** 20 (phone) / 30 (iPad) each side.
- Uses **PHCachingImageManager** with `carouselThumbnailSize`, `carouselThumbnailOptions()` (fastFormat, fast resize), and proper `stopCaching` when the window moves so strip scrolling hits PH cache.

### 5.4 When thumbnails are requested

- **Initial:** `loadInitialCarouselThumbnails()` loads first 15 (phone) or 30 (iPad) indices.
- **Scroll:** `loadVisibleAndNearbyThumbnails()` uses visible index paths ±10 and calls `loadThumbnailAtIndex` for each.
- **Prefetch:** `UICollectionViewDataSourcePrefetching` prefetches and cancels via `loadThumbnailAtIndex` / cancel on `thumbnailLoadingTasks`.

### 5.5 Cell configuration

**`PhotoCarouselCell.configure(with image: UIImage?, isCurrentPhoto: Bool, isVideo: Bool)`**

- If `image != nil`: set `imageView.image`, stop placeholder spinner.
- If `image == nil`: clear image, show spinner.
- Selection ring and video indicator updated; non-selected cells with image use alpha 0.65.

**`cellForItemAt` (carousel):** Passes `carouselThumbnails[indexPath.item]`; if nil, also calls `loadThumbnailAtIndex(indexPath.item)`.

So carousel strip images come from **carouselThumbnails** → filled by **loadThumbnailImage** → **ImageCacheService** (150×150) + **ImageDecodingService**, with PH preheat for the strip.

---

## 6. Face Chips (Detected Faces)

**Purpose:** Each detected face is shown as a small circle with optional name and checkmark.

### 6.1 Data model

**`DetectedFaceInfo`** (private struct):

- **`displayImage: UIImage`** — Crop used in the face chip (tighter).
- **`image: UIImage`** — Wider crop used when saving to contact photo.
- **`boundingBox: CGRect`**, **`facePrint: Data?`**.

### 6.2 Where displayImage comes from

**`detectAndCheckFaceDiversity(_ image: UIImage)`** (runs on background queue):

1. **VNDetectFaceRectanglesRequest** + **VNDetectFaceLandmarksRequest** on the current photo image.
2. For each **VNFaceObservation**:  
   - **Overlay chip:** `FaceCrop.expandedRect(..., scale: FaceCrop.overlayScale)` → **overlayScale = 2.5** (tighter crop).  
   - **Contact photo:** `FaceCrop.expandedRect(..., scale: FaceCrop.contactPhotoScale)` → **contactPhotoScale = 4.2**.  
3. **CGImage cropping:**  
   - `overlayRect` → `overlayCrop` → **`displayImage = UIImage(cgImage: overlayCrop)`**.  
   - `saveRect` → **`image`** (and boundingBox) for saving.

So face chip images are **in-memory crops** from the already-loaded main photo (no PHAsset or cache key). They are created once per face detection and held in **`detectedFaces: [DetectedFaceInfo]`**.

### 6.3 Display in UI

**`FaceCell.configure(with image: UIImage, name: String, isNamed: Bool)`**

- **`imageView.image = image`** (the `displayImage`).
- **imageView:** 50×50, `scaleAspectFill`, corner radius 25, white border; green status + checkmark when named.

**`cellForItemAt` (faces):** `cell.configure(with: faceInfo.displayImage, name: assignedName, isNamed: isNamed)`.

**FaceCrop** (`FaceCrop.swift`): `expandedRect(for:imageSize:scale:)` expands the Vision bounding box by a factor so the chip shows a consistent amount of context (overlay vs contact photo).

---

## 7. Name Suggestions (Autocomplete)

**`NameSuggestionCell.configure(name: String, photoData: Data)`**

- **thumbnailView:** 32×32, aspect fill, rounded. If `photoData` is non-empty and `UIImage(data: photoData)` succeeds, that image is shown; else placeholder background.

The **photoData** is the contact’s photo (or similar) passed from the view controller when building the suggestions list. It is **not** from PHAsset in this screen; it comes from the Contact model (e.g. thumbnail or photo data). So this path is **contact photo data → UIImage → thumbnail**, not the Name Faces asset pipeline.

---

## 8. Shared Services

### 8.1 ImageCacheService

**File:** `ImageCacheService.swift`

- **NSCache<NSString, UIImage>** with ~50 MB total cost and count limit 200.
- **Cost:** `estimateCost(for: image)` = width × height × 4.
- **Keys:** From **CacheKeyGenerator**: `"\(asset.localIdentifier)_\(w)x\(h)@\(scale)x"` so same asset at different sizes don’t collide.
- On memory warning: limits reduced and cache cleared.

Used for:

- Main display (2048 and display size),
- Carousel thumbnails (150×150).

### 8.2 CacheKeyGenerator

**File:** `ImageCacheService.swift` (same file)

- **`key(for asset: PHAsset, size: CGSize) -> String`** — `localIdentifier` + size dimensions + screen scale. Ensures correct resolution per device and size.

### 8.3 ImageDecodingService

**File:** `ImageDecodingService.swift`

- **`decodeForDisplay(_ image: UIImage?) async -> UIImage?`** — Draws image into a bitmap on a dedicated queue so the result is decoded and doesn’t cause main-thread decode when assigned to a UIImageView.
- Used after PH returns an image for main and carousel thumbnails before caching/display.

### 8.4 PHCachingImageManager

**WelcomeFaceNamingViewController** uses its own **`imageManager = PHCachingImageManager()`** (not `PhotoLibraryService`’s) for:

- **Display cache window:** `startCachingDisplayImages(around:)` with `displayImageSize`.
- **Carousel strip window:** `startCachingCarouselThumbnails(around:)` with `carouselThumbnailSize`.

So PH’s internal cache is warmed for the exact sizes used by the VC.

---

## 9. Memory and Lifecycle

- **Memory warning** (`handleMemoryWarningNotification`):  
  - Clears **cachedDisplayImages**.  
  - Keeps only carousel thumbnails near **currentCarouselIndex** (window ±10), cancels and clears other thumbnail tasks and slots.
- **Display cache eviction:** Indices outside `center ± (cacheWindowSize + displayCacheBuffer)` are removed from **cachedDisplayImages**; carousel thumbnails outside a smaller margin are nilled.
- **Cancellation:** `mainImageLoadTask` is cancelled when the user scrolls or taps another item so stale results aren’t applied. Thumbnail tasks are cancelled on prefetch cancel and when cleaning up on memory warning.

---

## 10. End-to-End Flow Summary

1. **SwiftUI:** Builds `[PHAsset]` (cache or fetch), optionally trims screenshots with 0 faces, passes assets into **WelcomeFaceNamingViewController**.
2. **Main photo:**  
   - On index change, **loadPhotoAtCarouselIndex** runs.  
   - Prefer **cachedDisplayImages[index]**; else placeholder from **carouselThumbnails[index]** then **loadOptimizedImage** (2048, **ImageCacheService**, decode).  
   - Result set on **photoImageView** (or video layer for video).
3. **Display cache:** **startCachingDisplayImages(around:)** keeps a window of display-size images in **cachedDisplayImages** and **ImageCacheService**, and uses PH preheat; scroll and restore use this for instant main image.
4. **Carousel strip:** **carouselThumbnails** filled by **loadThumbnailAtIndex** → **loadThumbnailImage** (150×150, **ImageCacheService**, decode), with PH strip preheat and prefetch; **PhotoCarouselCell** shows image or spinner.
5. **Face chips:** From **detectAndCheckFaceDiversity** on the current main image; **FaceCrop.overlayScale** crops → **DetectedFaceInfo.displayImage** → **FaceCell**.
6. **Name suggestions:** Contact **photoData** → **UIImage** in **NameSuggestionCell**; not part of the PH asset image pipeline.

All asset-derived images (main, display cache, carousel strip) go through **CacheKeyGenerator** and **ImageCacheService** by size; main and strip also use **ImageDecodingService** to avoid main-thread decode jank.

---

## 11. The 20% That Does 80% of the Improvement

If you could only keep or optimize a small slice of this implementation, these are the high-leverage pieces (by impact vs. code size).

### 1. Display cache + “show cached on scroll” (instant scroll)

**What:** `cachedDisplayImages` and using it in **scrollViewDidScroll** and **loadPhotoAtCarouselIndex** so the main photo updates immediately when the user scrolls, without waiting on a new request.

**Where:**  
- `WelcomeFaceNamingViewController`: `cachedDisplayImages` (dict), **startCachingDisplayImages(around:)** (~60 lines), and in **scrollViewDidScroll** the block that does `if let cachedImage = cachedDisplayImages[centeredIndex] { applyMainImage(...) }`.  
- In **loadPhotoAtCarouselIndex**, the branch that uses `cachedDisplayImages[index]` first.

**Why 80%:** Without this, every scroll would show a blank or stale image until a new PH request finished. This single behavior makes the carousel feel like Photos.

---

### 2. “Cache → placeholder → load” in loadPhotoAtCarouselIndex

**What:** For the main photo, always try **cached display image** first, then **carousel thumbnail** as placeholder, then **loadOptimizedImage**. One clear priority order.

**Where:** **loadPhotoAtCarouselIndex** (image branch): check `cachedDisplayImages[index]` → else optional `carouselThumbnails[index]` placeholder → then `loadOptimizedImage(for: asset)` and apply.

**Why 80%:** Eliminates blank main area and visible “pop” when the image loads. Most of the perceived quality comes from never showing nothing.

---

### 3. ImageDecodingService before display/cache

**What:** Decode every PH result (main + carousel thumb) with **ImageDecodingService.decodeForDisplay** before assigning to a UIImageView or putting in the cache.

**Where:** **ImageDecodingService.swift** (small file). Call sites: in **startCachingDisplayImages** callback and in **loadOptimizedImage** / **loadThumbnailImage** after receiving the image.

**Why 80%:** First assignment to a UIImageView with an undecoded image does decode on the main thread and causes jank. Doing it once off-main removes most scroll and load hitches.

---

### 4. One cache key + one shared ImageCacheService

**What:** **CacheKeyGenerator.key(for: size:)** and storing/reading all display and thumbnail images through **ImageCacheService** so the same asset at the same size is never re-requested or re-decoded unnecessarily.

**Where:** **ImageCacheService.swift** (cache + **CacheKeyGenerator**). Used in **loadOptimizedImage**, **loadThumbnailImage**, and **startCachingDisplayImages**.

**Why 80%:** Without a single key format and shared cache, you’d duplicate work across main photo, display cache, and carousel strip and waste memory and CPU.

---

### 5. PHCachingImageManager window (start + stop)

**What:** Call **startCachingImages** for a window around the current index and **stopCachingImages** for assets that left the window, so PH’s internal cache is warmed for exactly what you’re about to show, and you don’t cache the whole library.

**Where:** **startCachingDisplayImages(around:)** and **startCachingCarouselThumbnails(around:)** — the logic that computes the window, calls **startCachingImages** for the new window, and **stopCachingImages** for the old (using **lastCachedDisplayWindow** / **lastCarouselThumbnailWindow**).

**Why 80%:** This is what makes PH’s cache actually help; without a moving window you either cache too much (memory kill) or get no benefit.

---

### 6. Evict by distance from center

**What:** Remove **cachedDisplayImages** entries and **carouselThumbnails** slots that are far from the current index so memory doesn’t grow unbounded when scrolling through thousands of items.

**Where:** Inside **startCachingDisplayImages**: the loop that removes keys outside `[start - displayCacheBuffer, end + displayCacheBuffer]` and the loop that sets `carouselThumbnails[i] = nil` outside the thumb margin.

**Why 80%:** Without eviction, long scrolling sessions would hold hundreds of full-size images and get jetsam’d. This keeps the app stable.

---

### 7. Cancel in-flight work on scroll / index change

**What:** When the user changes the centered index (scroll or tap), cancel **mainImageLoadTask** and, for prefetch, cancel **thumbnailLoadingTasks** for items that scroll out.

**Where:** **scrollViewWillBeginDragging** (mainImageLoadTask?.cancel()). **loadPhotoAtCarouselIndex** (mainImageLoadTask?.cancel() at start). **cancelPrefetchingForItemsAt** (thumbnail task cancel). Guard in apply callbacks with `currentCarouselIndex == index`.

**Why 80%:** Prevents stale images appearing after the user has already moved, and avoids wasting CPU/IO on work that’s no longer needed.

---

### 8. Opportunistic delivery + one fallback

**What:** Request main image with **deliveryMode = .opportunistic** and resume the async continuation only when the result is non-degraded (or after a 6s timeout with the last image).

**Where:** **requestDisplayImageOpportunistic(for:)** — the options and the callback that checks **PHImageResultIsDegradedKey** and the 6s **DispatchWorkItem** fallback.

**Why 80%:** Gets a fast first frame when possible and avoids waiting forever if only a degraded image ever arrives (e.g. iCloud).

---

### Summary table (20% → 80%)

| # | Piece | Main benefit |
|---|--------|----------------|
| 1 | Display cache + show on scroll | Instant main image when scrolling |
| 2 | Cache → placeholder → load order | No blank main area |
| 3 | ImageDecodingService before display | Smooth scrolling, no first-draw jank |
| 4 | CacheKeyGenerator + ImageCacheService | No duplicate loads/decodes |
| 5 | PH window (start/stop caching) | PH cache actually helps, bounded memory |
| 6 | Evict by distance from center | Stable memory over long scroll |
| 7 | Cancel tasks on scroll/prefetch | No stale images, less wasted work |
| 8 | Opportunistic + 6s fallback | Fast when possible, robust on iCloud |

If you’re refactoring or porting, preserving these eight behaviors will retain most of the perceived performance and stability of the current implementation.
