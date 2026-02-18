# Why the Higher-Fidelity Image Sometimes Doesn’t Replace the Lower-Fidelity One (Name Faces)

## Symptom

In the Name Faces view, a higher-fidelity image sometimes loads but the main photo area keeps showing the lower-fidelity version instead of updating to the better one.

## Root Cause: Display Cache + Opportunistic Delivery Race

The main photo can come from two paths:

1. **Display cache** (`cachedDisplayImages[index]`) – used when you scroll or when the cache already has an image for that index (1024×1024 phone / 1440×1440 iPad).
2. **Explicit load** (`loadOptimizedImage` at 2048×2048) – used when there is no cached display image; supports “first delivery” (often degraded) then final image.

The bug is in how the **display cache** is filled.

### How the display cache is filled

In `startCachingDisplayImages(around:)`, for each index in the window we call:

```swift
imageManager.requestImage(
    for: asset,
    targetSize: displayImageSize,
    contentMode: .aspectFill,
    options: displayImageOptions()  // deliveryMode = .opportunistic
) { [weak self] image, _ in
    guard let self = self, let image = image else { return }
    Task {
        let decoded = await ImageDecodingService.decodeForDisplay(image)
        let toStore = decoded ?? image
        self.imageCache.setImage(toStore, for: cacheKey)
        await MainActor.run {
            self.cachedDisplayImages[i] = toStore
        }
    }
}
```

`displayImageOptions()` uses **`.opportunistic`** delivery. With that mode, Photos can invoke the completion handler **more than once**:

- Often: first a **degraded** (lower-quality) image, then a **full-quality** image.
- The order and timing of these callbacks are **not guaranteed**.

The callback **ignores the `info` dictionary**, so it never checks `PHImageResultIsDegradedKey`. It always:

1. Decodes the image.
2. Stores it in `ImageCacheService`.
3. Sets `cachedDisplayImages[i] = toStore`.

So **every** delivery (degraded and full) triggers a `Task` that eventually writes to the same cache key and the same `cachedDisplayImages[i]`. Because the two `Task`s run asynchronously, **whichever finishes last wins**. If the degraded image’s task completes after the full-quality one, it **overwrites** both the in-memory cache and `ImageCacheService` with the lower-fidelity image.

So we can end up with:

- `cachedDisplayImages[i]` = degraded image  
- `ImageCacheService` (for that asset + size) = degraded image  

even though the full-quality image was delivered and briefly stored.

### Why the UI never “replaces” with high fidelity

When you land on an index:

- `loadPhotoAtCarouselIndex(index)` runs.
- It checks `cachedDisplayImages[index]` first.
- If present, it calls `applyMainImage(cached, ...)` and **does not** call `loadOptimizedImage`.
- So the main photo is **only** what’s in the display cache.

If that cache slot was overwritten by the degraded image (due to the race above), the main area shows the low-fidelity image and we **never** request or apply the 2048 version, because we consider the slot “already filled.”

So: the higher-fidelity image **was** delivered and briefly stored, but a later callback overwrote it with the lower-fidelity one, and the UI only ever uses that cached (degraded) value.

## Secondary path (loadOptimizedImage)

When there is **no** cached display image, we use:

- Placeholder (e.g. carousel thumbnail) then
- `loadOptimizedImage(for: asset, onFirstDelivery: onFirst)`.

That path uses `requestDisplayImageOpportunistic`, which:

- Calls `onFirstDelivery` with the first image (possibly degraded) so the UI can show something immediately.
- Resumes the continuation only when `!isDegraded` (or after a 6s fallback with the last image).
- The caller then applies the returned image with `applyMainImage(loadedImage, ...)`.

So in that path we **do** replace the first (possibly low-fidelity) image with the final one when the continuation resumes, and we correctly ignore degraded results for the “final” image. The bug is **not** in this path; it’s in the display cache path that ignores `isDegraded` and allows a later degraded result to overwrite a full-quality one.

## Fix

In the display cache callback in `startCachingDisplayImages`:

1. Use the `info` parameter and read `PHImageResultIsDegradedKey`.
2. **If the image is degraded:**  
   - Update `cachedDisplayImages[i]` and `ImageCacheService` **only if** we don’t already have an image for this index (so we still show something quickly).
3. **If the image is not degraded:**  
   - **Always** update both the in-memory cache and `ImageCacheService` so we replace any placeholder or degraded image with full quality and never overwrite high-fidelity with low-fidelity.

This preserves fast initial display (we can still show the first, possibly degraded, image when the slot is empty) while ensuring that once a full-quality image arrives, it is never replaced by a degraded one.

## Summary

| Item | Detail |
|------|--------|
| **Symptom** | Higher-fidelity image sometimes doesn’t replace the lower-fidelity one in the main photo area. |
| **Cause** | Display cache uses opportunistic delivery but ignores `isDegraded`. Two callbacks (degraded + full) both write to the same slot; async ordering can let the degraded write happen last and overwrite the full-quality image. |
| **Why it sticks** | When the cache has a value we use it and never call `loadOptimizedImage`, so the main area never gets the 2048 version. |
| **Fix** | In the display cache callback, only update when `!isDegraded`, or when degraded and the slot is still empty. Never overwrite an existing (possibly full-quality) cache entry with a degraded image. |
