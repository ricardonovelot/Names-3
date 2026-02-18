# Deep Analysis: Carousel Window vs Magnifying Glass (Next Photo) Clash

## Summary

Two independent logics conflict:

1. **Carousel window logic** — Only a bounded set of assets (500) is in the carousel at once. More assets are loaded only when the **user scrolls** near the end of the strip (within 80 items of the end).
2. **Magnifying glass logic** — The “Next” button finds the **next photo with 2+ faces** by draining a queue filled from **preprocessNextBatch()**, which only ever reads from **prioritizedAssets**.

Because the magnifying glass never triggers loading more assets, it can only find the “next relevant photo” **within the current window**. As soon as the next such photo lies beyond the loaded set (e.g. at index 501+), the flow hits “No more batches” and shows “No more photos” even though more relevant photos exist in the library.

---

## 1. Where Each Logic Lives

### 1.1 Carousel asset list (bounded window)

| Layer | File | What happens |
|-------|------|----------------|
| **SwiftUI** | `WelcomeFaceNamingView.swift` | Loads **500** assets with `fetchInitialAssets(limit: 500)` and passes them to the VC as `prioritizedAssets`. No further fetch from this layer. |
| **VC** | `WelcomeFaceNamingViewController.swift` | Holds `prioritizedAssets` (carousel data source). Can **grow** the window only via **scroll**: when `scrollViewDidScroll` (or similar) sees the centered index within **80** items of the end, it calls **slideWindowForwardIfNeeded(centerIndex:)**. That fetches **120** older assets with `fetchAssetsOlderThan(lastDate, limit: 120)`, drops the first 120, appends the new batch, and updates the collection view. |

So “more assets” are only added when the user **physically scrolls** the carousel near the end. If the user never scrolls and only uses the magnifying glass, the window stays at 500.

### 1.2 Magnifying glass (“Next” photo with 2+ faces)

| Component | Location | What it does |
|-----------|----------|----------------|
| **Button** | Liquid glass “magnifying glass” → `nextPhotoTapped()` → **loadNextPhotoWithFaces()** | Kicks off the “find next relevant photo” flow. |
| **Queue** | **photoQueue: [PhotoCandidate]** | Holds candidates (asset + face count + index) that have **already** been preprocessed. |
| **Preprocessing** | **preprocessNextBatch()** | Runs in batches of 30 over **prioritizedAssets**: from `currentBatchIndex` to `currentBatchIndex + 30`, loads image, counts faces (Vision), and if face count ≥ 2 appends to **photoQueue**. Advances **currentBatchIndex** by 30. |
| **Search loop** | Inside **loadNextPhotoWithFaces()** | While `!photoQueue.isEmpty || currentBatchIndex < prioritizedAssets.count`: if queue empty → call **preprocessNextBatch()** and wait; else take next candidate **after** `currentCarouselIndex`, apply time-dedupe and “new faces” checks, then show that photo and return. When **currentBatchIndex ≥ prioritizedAssets.count** and queue is empty → break and show **“No more photos”**. |

Important: the search loop **only** ever reads from **prioritizedAssets** and **photoQueue**. It never asks to load more assets from the library.

---

## 2. How They Clash

- **Carousel** has at most 500 items (or the current window after slides). More items appear only when **scroll** triggers **slideWindowForwardIfNeeded**.
- **Magnifying glass** looks for the next good photo only in **prioritizedAssets**. When it has drained the queue and **currentBatchIndex >= prioritizedAssets.count**, it stops and shows “No more photos”.

So:

- If the next photo with 2+ faces is at “index 600” in the library, but the carousel only has 500 items, that photo is **not** in **prioritizedAssets**. The magnifying glass will never see it.
- The only way to get that photo into **prioritizedAssets** today is to **scroll** the carousel near the end so that **slideWindowForwardIfNeeded** runs and appends a new batch. The user has no way to “fetch more” by using the magnifying glass alone.

Result: **Magnifying glass is blocked by the carousel’s “only load more on scroll” rule.**

---

## 3. Secondary issue: slide window and preprocessing

When the window **does** slide forward (user scrolled near the end):

- **slideWindowForwardIfNeeded** replaces the first 120 items with 120 newer (older-date) assets at the **end** of **prioritizedAssets**.
- It clears **photoQueue** but **does not** update **currentBatchIndex**.
- So after the slide, the “new” items are at indices `(oldCount - 120)..<oldCount` (e.g. 380..<500). **currentBatchIndex** is still 500 (or whatever it was). So **preprocessNextBatch()** thinks there is nothing left to process (`currentBatchIndex < prioritizedAssets.count` is false), and the new tail never gets added to **photoQueue**. So even after a scroll-triggered slide, the magnifying glass won’t see those new items until some other path resets or advances **currentBatchIndex**.

---

## 4. Intended behavior (recommended)

1. **Magnifying glass** should be able to find the next relevant photo **even when that photo is beyond the current window**. So when the search is about to give up (**currentBatchIndex >= prioritizedAssets.count** and queue empty), it should **first** try to load more assets (e.g. same mechanism as sliding the window: fetch next chunk older than **prioritizedAssets.last** and append, or trigger a slide), then continue the search. Only show “No more photos” when the library truly has no more assets to fetch.
2. **After sliding the window forward**, **currentBatchIndex** should be set so that the new tail (e.g. indices 380..<500) is considered “not yet preprocessed” (e.g. set **currentBatchIndex = min(currentBatchIndex, oldCount - dropCount)**), and optionally trigger **preprocessNextBatch()** so **photoQueue** is filled for the new range.

---

## 5. Code references (key lines)

| Concept | File | Approx. lines |
|--------|------|----------------|
| Initial 500 assets | `WelcomeFaceNamingView.swift` | 14, 37–39 |
| Sliding window trigger (scroll only) | `WelcomeFaceNamingViewController.swift` | 3118–3119 |
| slideWindowForwardIfNeeded | `WelcomeFaceNamingViewController.swift` | 1806–1843 |
| loadNextPhotoWithFaces loop | `WelcomeFaceNamingViewController.swift` | 1884–2054 |
| preprocessNextBatch (only prioritizedAssets) | `WelcomeFaceNamingViewController.swift` | 1510–1579 |
| “No more photos” when queue/batch exhausted | `WelcomeFaceNamingViewController.swift` | 2046–2052 |
| currentBatchIndex never updated after slide | `WelcomeFaceNamingViewController.swift` | 1812–1840 (no currentBatchIndex update) |

---

## 6. Fix checklist

- [x] **When magnifying glass exhausts the queue** (currentBatchIndex >= prioritizedAssets.count): before showing “No more photos”, try to **fetch more assets** (e.g. fetch next chunk older than last asset, append to **prioritizedAssets**, extend carousel). If new assets were added, set **currentBatchIndex** so the new tail is preprocessed and continue the search loop; otherwise show “No more photos”.
- [x] **When sliding the window forward**: set **currentBatchIndex = min(currentBatchIndex, oldCount - dropCount)** and call **preprocessNextBatch()** so the new tail is processed.
- [x] **When sliding the window backward**: set **currentBatchIndex = 0** and call **preprocessNextBatch()** so the new batch at the start is processed.

This keeps the carousel’s bounded-window and scroll-triggered slide behavior, while allowing the magnifying glass to “pull in” more of the library when needed so the two logics no longer clash.
