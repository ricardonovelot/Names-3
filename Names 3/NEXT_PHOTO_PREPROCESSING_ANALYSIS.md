# Deep Analysis: Why “Next Photo” Preprocessing Feels Slow

## 1. What the wait loops do

After the two changes (“wait for preprocessing when queue is empty” and “wait for batch when candidate behind”):

- When the queue is empty we call **preprocessNextBatch()** once, then **wait** (poll every 200ms, up to 20s) until either the queue has items or we’ve reached the end of the asset list.
- When the only candidate is behind the current index we call **preprocessNextBatch()** once, then **wait** the same way (20s max).

So we no longer spin with 10 quick attempts; we actually wait for the batch. That makes the **real cost of one batch** very visible: the whole “Next” action is slow because the batch itself is slow.

---

## 2. Where the time goes: preprocessNextBatch()

### 2.1 Image load: too heavy for “face count only”

- **preprocessNextBatch()** uses **loadOptimizedImage(for: asset)** for every image in the batch.
- **loadOptimizedImage** is built for **main photo display**:
  - Requests at **mainDisplayTargetSize = 2048×2048**.
  - Uses **requestDisplayImageOpportunistic** (can wait up to **6 seconds** per image if only degraded is available).
  - Runs **ImageDecodingService.decodeForDisplay** (full decode for sharp display).

For **only counting faces** we don’t need 2048 or a display-quality decode. Vision face detection is fine at **512×512 or 1024×1024**. So we’re doing roughly **4–16× more pixels** per image (2048² vs 512²–1024²), plus a 6s risk per asset, for work that doesn’t need it.

**Effect:** Each of the ~18 images in a batch pays the cost of a full-screen load instead of a small preprocessing load → batch time is much longer than necessary.

### 2.2 Fully sequential work

- The batch loop is **strictly sequential**:
  - For each asset: `await loadOptimizedImage(for: asset)` then `await countFaces(in: image)`.
- So we never overlap:
  - I/O for image N+1 doesn’t start until image N is fully loaded and face-counted.
  - Only one image is in flight at a time; extra CPU/cores aren’t used.

**Effect:** Total batch time = sum of (load + face count) per image, with no parallelism → longer wall-clock time.

### 2.3 Batch size and timeout

- Batch size is **18** (images only; videos skipped).
- Per image (with current load): ~0.2–6+ seconds (cache hit vs full 2048 load + possible 6s wait).
- So one batch can easily take **20–60+ seconds**, but the wait loops **time out at 20 seconds**.
- When we hit the timeout we **continue** and, on the next iteration, call **preprocessNextBatch()** again. If the first batch is still running, **guard !isPreprocessing** causes that call to **do nothing**, and we **wait another 20 seconds** with no new work started.

**Effect:** We can burn 20s + 20s (or more) with no progress, and the user sees “loading” for a long time.

---

## 3. Summary: why it feels “super slow”

| Cause | Effect |
|--------|--------|
| Preprocessing uses 2048×2048 (and 6s fallback) per image | Much more I/O and decode than needed for face count; batch takes 20–60+ s. |
| Sequential load + face count | No overlap of I/O or use of multiple cores; wall time = sum of all steps. |
| 20s wait timeout | If batch takes >20s we timeout, then wait again while isPreprocessing is still true → long stretches of “loading” with no visible progress. |
| No “batch finished” check in wait | We only break when queue has items or we’re at end; we don’t break when the batch has finished but found no faces, so we sometimes wait the full 20s after the batch is done. |

---

## 4. Recommended changes

1. **Lightweight image path for preprocessing only**
   - Add a **preprocessing-only** load (e.g. 512×512 or 1024×1024) with its own cache key.
   - Use it **only** in preprocessNextBatch(); keep **loadOptimizedImage** for display and for the chosen candidate.
   - Reduces per-image time and avoids the 6s display fallback for batch work.

2. **Parallelize within the batch**
   - Process multiple assets **concurrently** (e.g. 4 at a time via TaskGroup or similar).
   - Overlap I/O and CPU so one batch finishes in “max over 4” instead of “sum of 18”.

3. **Smarter wait loops**
   - **Break when isPreprocessing becomes false** (batch finished), not only when queue has items or at end.
   - Avoids sitting in the wait loop for the full 20s after the batch has already completed (whether it found faces or not).
   - Optionally **increase timeout** (e.g. 45s) so a single heavy batch has time to complete before we give up.

4. **Keep batch size and polling as-is for now**
   - After 1–3, each batch should be much faster, so 18 items and 200ms polling are reasonable.

**Implemented:**
- **Lightweight path:** `loadImageForPreprocessing(for:)` requests at 512×512 with `.fastFormat`, 2s timeout, separate cache key; used only in preprocessNextBatch.
- **Parallelism:** Batch processes in chunks of 4 via `withTaskGroup` (load + face count per asset concurrently).
- **Wait loops:** Break when `!isPreprocessing` (batch finished) as well as when queue has items or at end; timeout 30s, poll 150ms.
