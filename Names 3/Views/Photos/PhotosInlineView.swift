import SwiftUI
import SwiftData
import Photos

struct PhotosInlineView: View {
    let contactsContext: ModelContext
    let isVisible: Bool
    let onPhotoPicked: (UIImage, Date?) -> Void
    
    @StateObject private var viewModel = InlinePhotosViewModel()
    @State private var faceDetectionViewModel: FaceDetectionViewModel?
    
    init(contactsContext: ModelContext, isVisible: Bool = true, onPhotoPicked: @escaping (UIImage, Date?) -> Void) {
        self.contactsContext = contactsContext
        self.isVisible = isVisible
        self.onPhotoPicked = onPhotoPicked
    }
    
    var body: some View {
        ZStack {
            if viewModel.assets.isEmpty {
                ProgressView("Loading recent photos...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PhotoGridView(
                    assets: viewModel.assets,
                    imageManager: PHCachingImageManager(),
                    contactsContext: contactsContext,
                    initialScrollDate: nil,
                    onPhotoTapped: { image, date, _ in
                        onPhotoPicked(image, date)
                    },
                    onAppearAtIndex: { _ in },
                    onDetailVisibilityChanged: { _ in },
                    faceDetectionViewModelBinding: $faceDetectionViewModel
                )
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            if viewModel.assets.isEmpty {
                viewModel.loadRecentPhotos()
            }
        }
    }
}

// MARK: - Inline Photos ViewModel

@MainActor
final class InlinePhotosViewModel: ObservableObject {
    @Published private(set) var assets: [PHAsset] = []
    
    private let recentPhotosLimit = 300
    
    func loadRecentPhotos() {
        Task {
            let status = await PhotoLibraryService.shared.requestAuthorization()
            guard status == .authorized || status == .limited else { return }
            
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = recentPhotosLimit
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            
            let fetchResult = PHAsset.fetchAssets(with: options)
            var loadedAssets: [PHAsset] = []
            loadedAssets.reserveCapacity(fetchResult.count)
            
            fetchResult.enumerateObjects { asset, _, _ in
                loadedAssets.append(asset)
            }
            
            assets = loadedAssets.reversed()
        }
    }
}
