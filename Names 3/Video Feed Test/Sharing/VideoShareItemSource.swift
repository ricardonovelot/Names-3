import UIKit
import LinkPresentation

final class VideoShareItemSource: NSObject, UIActivityItemSource {
    private let url: URL
    private let title: String?
    private let previewImage: UIImage?

    init(url: URL, title: String?, previewImage: UIImage?) {
        self.url = url
        self.title = title
        self.previewImage = previewImage
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return url
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let meta = LPLinkMetadata()
        if let title { meta.title = title }
        if let image = previewImage {
            meta.iconProvider = NSItemProvider(object: image)
            meta.imageProvider = NSItemProvider(object: image)
        }
        meta.originalURL = url
        return meta
    }
}