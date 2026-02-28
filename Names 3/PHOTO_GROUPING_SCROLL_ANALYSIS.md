# Photo Grouping Mode Scroll Blocking — Complete Code Analysis

## Summary

Photo grouping mode affects feed scrolling. Only **"Between Videos"** allows smooth scrolling; **"Off"**, **"By Day"**, and **"By Count"** block or severely limit scrolling. This document analyzes the cause and relevant code paths.

---

## 1. Architecture Overview

### Two Feed Implementations

| Component | Used By | Scroll Gate? |
|-----------|---------|--------------|
| **TikTokFeedViewController** → **FeedPagedCollectionViewController** | Main app (NameFacesFeedCombinedView) | **No** |
| **TikTokFeedView** → **PagedCollectionView** | Video Feed Test app (VideoFeedContentView) | **Yes** |

**Main app flow:** `ContentView` → `NameFacesFeedCombinedView` → `NameFacesFeedCombinedViewController` → `TikTokFeedViewController` → `FeedPagedCollectionViewController`

**Video Feed Test flow:** `VideoFeedContentView` → `TikTokFeedView` → `PagedCollectionView`

---

## 2. Root Cause: Scroll Gate in PagedCollectionView

### Location

`Names 3/Video Feed Test/PagedCollectionView.swift`, lines 273–312

### Behavior

`scrollViewDidScroll` enforces a **scroll gate** that limits how far the user can scroll before the next page is "ready":

```swift
// Lines 285–308
let h = collectionView.bounds.height
let current = indexBinding.wrappedValue
let baseY = h * CGFloat(current)
let y = scrollView.contentOffset.y
let delta = y - baseY
guard delta > 0 else { hideGateSpinner(); return }

var i = current + 1
while items.indices.contains(i), isPageReady(i) {
    i += 1
}
guard items.indices.contains(i) else { hideGateSpinner(); return }

let readySpan = max(0, i - current - 1)
let cap = CGFloat(readySpan) * h + h * gateFraction  // gateFraction = 0.2
if delta > cap {
    scrollView.contentOffset.y = baseY + cap  // ← BLOCKS SCROLL
    if scrollView.isDragging { showGateSpinner() }
}
```

- `readySpan` = number of consecutive ready pages ahead of the current page.
- `cap` = how far the user can scroll (in points).
- If the user scrolls beyond `cap`, `contentOffset` is clamped to `baseY + cap`.

### `isPageReady` Logic

- **Video:** `true` only when the video is in `readyVideoIDs` (prefetched).
- **Photo carousel:** always `true`.

So the gate only blocks when the next page is a **video** that is not yet prefetched.

---

## 3. Why "Between Videos" Works and Others Don't

### Feed Item Structure by Mode

| Mode | Interleave Logic | Typical Pattern |
|------|------------------|-----------------|
| **Between Videos** | `interleaveBetweenVideo` | `v, c, v, c, v, c` |
| **By Day / By Count** | `interleaveByStride` | `v, v, v, v, v, c, v, v, v, v, v, c` |
| **Off** | Videos only | `v, v, v, v, v` |

### Between Videos

- Alternating video and carousel.
- When on a **video**, next page is a **carousel** → always ready → `readySpan ≥ 1` → can scroll.
- When on a **carousel**, next page is a **video** → may not be ready → `readySpan = 0` → cap = 0.2h → scroll blocked until video prefetches.

Because carousels are frequent, many transitions are video→carousel, so scrolling feels usable.

### By Day / By Count

- Many consecutive videos (e.g. 5) between carousels.
- When on a **video**, next page is often another **video** → not ready → `readySpan = 0` → cap = 0.2h → scroll blocked.
- User is effectively stuck until the next video prefetches.

### Off

- Only videos.
- Every transition is video→video → same blocking behavior as By Day/By Count.

---

## 4. Console Logs Added for Debugging

The following `[PhotoGroupingScroll]` logs were added to trace scroll behavior:

### PagedCollectionView (Video Feed Test)

- **BLOCKING:** When the gate clamps scroll: `current`, `delta`, `readySpan`, `cap`, `nextPage` (video/carousel), `nextReady`
- **Gate:** When scrolling forward (first 5 pages): same fields for non-blocking case

### FeedPagedCollectionViewController (Main app)

- **willBeginDragging:** When user starts vertical scroll
- **page change:** When page index changes during scroll
- **didEndDragging:** When user releases (with decelerate flag)
- **didEndDecelerating:** When scroll animation completes

### TikTokFeedViewModel

- **Items published:** When feed items are set: `source`, `mode`, `count`, `V`/`C` counts, `pattern` (e.g. `VCVCVC` for Between Videos, `VVVVVC` for By Day)

### MediaFeedCellView (Main app carousel cells)

- **carousel willBeginDragging:** When user starts horizontal scroll on a photo carousel (helps detect gesture conflict)

### How to Use

1. Run the app (main app or Video Feed Test) and open the feed.
2. Change photo grouping mode in Settings.
3. Try to scroll and watch Xcode console for `[PhotoGroupingScroll]` logs.
4. **Video Feed Test + non–Between-Videos mode:** Expect `BLOCKING` logs when scroll is clamped; `nextPage=video nextReady=false` confirms gate is blocking.
5. **Main app:** If `willBeginDragging` never fires when you swipe vertically, the gesture may be captured by the carousel (check for `carousel willBeginDragging` instead).

---

## 5. Relevant Files

| File | Role |
|------|------|
| `Video Feed Test/PagedCollectionView.swift` | Scroll gate (lines 273–330) |
| `Video Feed Test/TikTokFeedViewModel.swift` | `buildFeedItemsFromMixedAssets`, `interleave`, `makeCarousels`, `logItemsStructure` |
| `Views/Feed/FeedPhotoGroupingMode.swift` | Grouping mode enum |
| `Views/Feed/FeedPagedCollectionViewController.swift` | Main app feed; no gate |
| `Views/Feed/MediaFeedCellView.swift` | Video + photo carousel cells |

---

## 6. Main App vs Video Feed Test

- **Main app** uses `FeedPagedCollectionViewController`, which has **no** scroll gate.
- **Video Feed Test** uses `PagedCollectionView`, which **does** have the gate.

If the issue appears in the main app, the cause is likely different (e.g. gesture conflicts). If it appears in the Video Feed Test app, the gate is the cause.

---

## 7. Possible Fixes (for PagedCollectionView)

1. **Remove or relax the gate**  
   - Remove the cap entirely, or  
   - Only apply it when the next page is a video and not ready, and allow a larger cap (e.g. full page).

2. **Treat photo carousels as "ready" for gate purposes**  
   - Already the case; the problem is the high density of videos in By Day/By Count/Off.

3. **Prefetch more aggressively**  
   - Expand the prefetch window so more videos are ready before the user reaches them.

4. **Gate only for videos**  
   - If the next page is a carousel, do not apply the cap.  
   - If the next page is a video, keep the gate but consider a larger allowed scroll (e.g. full page) instead of 0.2h.

---

## 8. Gesture Conflict (Secondary Consideration)

`MediaFeedCellView` embeds a horizontal `UICollectionView` for photo carousels. Nested scroll views can compete for pan gestures:

- Vertical swipes → outer vertical feed.
- Horizontal swipes → inner carousel.

By default, the system favors the scroll view with more scrollable distance in the gesture direction. Vertical swipes should still reach the outer feed. If blocking occurs even when the next page is a carousel, gesture handling may need review (e.g. `simultaneousGesture`, `gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:`).

---

## 9. Recommendation

1. Confirm which app/target shows the issue (main app vs Video Feed Test).
2. If Video Feed Test: adjust or remove the scroll gate in `PagedCollectionView.swift` (lines 273–312).
3. If main app: investigate gesture handling and nested scroll views in `MediaFeedCellView` and the feed container.
