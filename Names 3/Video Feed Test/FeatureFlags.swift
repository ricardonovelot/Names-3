import Foundation

enum FeatureFlags {
    static let enablePhotoPosts: Bool = true  // Photos in feed; grouping controlled by FeedPhotoGroupingMode
    static let enableAppleMusicIntegration: Bool = true

    static let forceSDRForHDRPlayback: Bool = true
    static let disableHDRMetadataOnPlayback: Bool = true
}