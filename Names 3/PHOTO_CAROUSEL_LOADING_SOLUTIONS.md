# Photo Carousel Loading

Two-tier cache for photo carousel loading in the feed. Uses `PhotoCarouselImageService`:

- **ThumbnailCache** (NSCache, 400px) for instant display
- **PHCachingImageManager** for full-res upgrade
- Always loads thumbnail first, then upgrades to full-res (progressive loading pattern used by Photos, Instagram)
