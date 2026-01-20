import SwiftUI
import UIKit
import Photos
import SwiftData
import Vision

// MARK: - PhotoGridView

struct PhotoGridView: UIViewRepresentable {
    let assets: [PHAsset]
    let imageManager: PHCachingImageManager
    let contactsContext: ModelContext
    let initialScrollDate: Date?
    let onPhotoTapped: (UIImage, Date?) -> Void
    let onAppearAtIndex: (Int) -> Void
    let onDetailVisibilityChanged: (Bool) -> Void
    @Binding var faceDetectionViewModelBinding: FaceDetectionViewModel?

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.systemGroupedBackground

        let layout = context.coordinator.makeCompositionalLayout()

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = UIColor.systemGroupedBackground
        collectionView.delegate = context.coordinator
        collectionView.prefetchDataSource = context.coordinator
        collectionView.alwaysBounceVertical = true
        collectionView.isPrefetchingEnabled = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseIdentifier)
        collectionView.register(PhotoFullscreenCell.self, forCellWithReuseIdentifier: PhotoFullscreenCell.reuseIdentifier)

        context.coordinator.configureDataSource(for: collectionView)

        let floatingHeader = FloatingDateHeaderView(frame: .zero)
        floatingHeader.translatesAutoresizingMaskIntoConstraints = false
        
        let carouselContainer = UIView()
        carouselContainer.translatesAutoresizingMaskIntoConstraints = false
        carouselContainer.backgroundColor = UIColor.systemGroupedBackground
        carouselContainer.alpha = 0
        carouselContainer.isUserInteractionEnabled = true

        containerView.addSubview(collectionView)
        containerView.addSubview(carouselContainer)
        containerView.addSubview(floatingHeader)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: containerView.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            floatingHeader.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor, constant: 8),
            floatingHeader.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            
            carouselContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            carouselContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            carouselContainer.bottomAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.bottomAnchor),
            carouselContainer.heightAnchor.constraint(equalToConstant: 120)
        ])

        context.coordinator.collectionView = collectionView
        context.coordinator.floatingHeader = floatingHeader
        context.coordinator.containerView = containerView
        context.coordinator.carouselContainer = carouselContainer
        context.coordinator.parentViewController = Self.findViewController(from: containerView)
        context.coordinator.installPinchGesture(on: collectionView)

        return containerView
    }
    
    private static func findViewController(from view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController
            }
            responder = currentResponder.next
        }
        return nil
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.updateAssets(assets, initialScrollDate: initialScrollDate)
        
        if context.coordinator.parentViewController == nil {
            context.coordinator.parentViewController = Self.findViewController(from: uiView)
        }
        
        uiView.setNeedsLayout()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            imageManager: imageManager,
            contactsContext: contactsContext,
            onPhotoTapped: onPhotoTapped,
            onAppearAtIndex: onAppearAtIndex,
            onDetailVisibilityChanged: onDetailVisibilityChanged,
            faceDetectionViewModelBinding: $faceDetectionViewModelBinding
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let imageManager: PHCachingImageManager
        let contactsContext: ModelContext
        let onPhotoTapped: (UIImage, Date?) -> Void
        let onAppearAtIndex: (Int) -> Void
        let onDetailVisibilityChanged: (Bool) -> Void
        
        private var faceDetectionViewModelGetter: () -> FaceDetectionViewModel?
        private var faceDetectionViewModelSetter: (FaceDetectionViewModel?) -> Void

        weak var collectionView: UICollectionView?
        weak var floatingHeader: FloatingDateHeaderView?
        weak var containerView: UIView?
        weak var carouselContainer: UIView?

        private var dataSource: UICollectionViewDiffableDataSource<Int, String>?
        private var sortedAssets: [PHAsset] = []
        private var deletedAssetIDs: Set<String> = []
        private var hasPerformedInitialScroll = false
        private var pendingScrollDate: Date?

        private let imageCache = ImageCacheService.shared
        private(set) var compositionalLayout: UICollectionViewCompositionalLayout?
        
        let availableColumns: [Int] = [1, 3, 5]
        private(set) var currentColumnIndex: Int = 1 // Start at 3 columns
        private let itemSpacing: CGFloat = 2
        private let sectionInsets = NSDirectionalEdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2)
        
        private var anchorIndex: Int?
        private var isZooming: Bool = false
        private var isPreparedForDismissal: Bool = false
        
        private var currentVisibleFullscreenIndex: Int?
        
        @MainActor private var currentFaceViewModel = FaceDetectionViewModel()
        private var carouselHostingController: UIHostingController<PhotoFaceCarouselView>?
        weak var parentViewController: UIViewController?

        init(
            imageManager: PHCachingImageManager,
            contactsContext: ModelContext,
            onPhotoTapped: @escaping (UIImage, Date?) -> Void,
            onAppearAtIndex: @escaping (Int) -> Void,
            onDetailVisibilityChanged: @escaping (Bool) -> Void,
            faceDetectionViewModelBinding: Binding<FaceDetectionViewModel?>
        ) {
            self.imageManager = imageManager
            self.contactsContext = contactsContext
            self.onPhotoTapped = onPhotoTapped
            self.onAppearAtIndex = onAppearAtIndex
            self.onDetailVisibilityChanged = onDetailVisibilityChanged
            
            self.faceDetectionViewModelGetter = { faceDetectionViewModelBinding.wrappedValue }
            self.faceDetectionViewModelSetter = { newValue in
                Task { @MainActor in
                    faceDetectionViewModelBinding.wrappedValue = newValue
                }
            }
            
            super.init()
            
            Task { @MainActor in
                self.currentFaceViewModel = FaceDetectionViewModel()
            }
        }

        // MARK: - Layout

        func makeCompositionalLayout() -> UICollectionViewCompositionalLayout {
            let configuration = UICollectionViewCompositionalLayoutConfiguration()
            
            let layout = UICollectionViewCompositionalLayout(sectionProvider: { [weak self] sectionIndex, environment in
                guard let self = self else { return nil }
                return self.createSectionLayout(environment: environment)
            }, configuration: configuration)
            
            self.compositionalLayout = layout
            return layout
        }

        private func createSectionLayout(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
            let columns = availableColumns[currentColumnIndex]
            
            if columns == 1 {
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .fractionalHeight(1.0)
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                
                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .fractionalHeight(1.0)
                )
                let group = NSCollectionLayoutGroup.vertical(
                    layoutSize: groupSize,
                    subitems: [item]
                )
                
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                section.interGroupSpacing = 0
                
                return section
            }
            
            let containerWidth = environment.container.contentSize.width
            let availableWidth = containerWidth - sectionInsets.leading - sectionInsets.trailing
            let totalSpacing = CGFloat(columns - 1) * itemSpacing
            let cellSide = floor((availableWidth - totalSpacing) / CGFloat(columns))
            
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .absolute(cellSide),
                heightDimension: .absolute(cellSide)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            
            let groupSize = NSCollectionLayoutSize(
                widthDimension: .absolute(availableWidth),
                heightDimension: .absolute(cellSide)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                subitem: item,
                count: columns
            )
            group.interItemSpacing = .fixed(itemSpacing)
            
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = itemSpacing
            section.contentInsets = sectionInsets
            
            return section
        }

        private func cellSizeForCurrentColumns() -> CGFloat {
            guard let collectionView = collectionView else { return 100 }
            let columns = availableColumns[currentColumnIndex]
            
            if columns == 1 {
                return collectionView.bounds.width
            }
            
            let availableWidth = collectionView.bounds.width - sectionInsets.leading - sectionInsets.trailing
            let totalSpacing = CGFloat(columns - 1) * itemSpacing
            return floor((availableWidth - totalSpacing) / CGFloat(columns))
        }
        
        private func updateScrollBehavior() {
            guard let collectionView = collectionView else { return }
            let columns = availableColumns[currentColumnIndex]
            
            if columns == 1 {
                // Fullscreen mode - disable paging, we'll handle snapping manually
                collectionView.isPagingEnabled = false
                collectionView.alwaysBounceVertical = true
                collectionView.decelerationRate = .fast
                floatingHeader?.alpha = 0
                
                // Update the current visible index
                updateCurrentVisibleFullscreenIndex()
                
                showCarousel()
            } else {
                // Grid mode
                collectionView.isPagingEnabled = false
                collectionView.alwaysBounceVertical = true
                collectionView.decelerationRate = .normal
                floatingHeader?.alpha = 1.0
                
                // Clear current visible index
                currentVisibleFullscreenIndex = nil
                
                hideCarousel()
                
                // Clear face detection when leaving fullscreen
                Task { @MainActor in
                    self.currentFaceViewModel.faces = []
                }
            }
        }
        
        private func showCarousel() {
            guard let carouselContainer = carouselContainer else { return }
            
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
                carouselContainer.alpha = 1.0
            }
        }
        
        private func hideCarousel() {
            guard let carouselContainer = carouselContainer else { return }
            
            UIView.animate(withDuration: 0.25) {
                carouselContainer.alpha = 0.0
            }
        }
        
        private func setupCarousel(with viewModel: FaceDetectionViewModel) {
            guard let carouselContainer = carouselContainer else { return }
            
            if let existingHosting = carouselHostingController {
                existingHosting.willMove(toParent: nil)
                existingHosting.view.removeFromSuperview()
                existingHosting.removeFromParent()
                carouselHostingController = nil
            }
            
            Task { @MainActor in
                guard !viewModel.faces.isEmpty else {
                    await MainActor.run {
                        self.hideCarousel()
                    }
                    return
                }
                
                let carouselView = PhotoFaceCarouselView(
                    viewModel: viewModel,
                    onFaceSelected: { [weak self] index in
                        guard let self = self else { return }
                        Task { @MainActor in
                            guard index >= 0, index < viewModel.faces.count else { return }
                            let faceImage = viewModel.faces[index].image
                            await MainActor.run {
                                if let visibleIndices = self.collectionView?.indexPathsForVisibleItems.map({ $0.item }).sorted().first,
                                   visibleIndices < self.sortedAssets.count {
                                    let asset = self.sortedAssets[visibleIndices]
                                    self.onPhotoTapped(faceImage, asset.creationDate)
                                }
                            }
                        }
                    }
                )
                
                await MainActor.run {
                    guard let parentVC = self.parentViewController else {
                        print("❌ [PhotoGrid] No parent view controller found for carousel")
                        return
                    }
                    
                    let hosting = UIHostingController(rootView: carouselView)
                    hosting.view.backgroundColor = UIColor.clear
                    hosting.view.translatesAutoresizingMaskIntoConstraints = false
                    
                    parentVC.addChild(hosting)
                    carouselContainer.addSubview(hosting.view)
                    hosting.didMove(toParent: parentVC)
                    
                    NSLayoutConstraint.activate([
                        hosting.view.topAnchor.constraint(equalTo: carouselContainer.topAnchor),
                        hosting.view.leadingAnchor.constraint(equalTo: carouselContainer.leadingAnchor),
                        hosting.view.trailingAnchor.constraint(equalTo: carouselContainer.trailingAnchor),
                        hosting.view.bottomAnchor.constraint(equalTo: carouselContainer.bottomAnchor)
                    ])
                    
                    self.carouselHostingController = hosting
                }
            }
        }

        // MARK: - Data Source

        func configureDataSource(for collectionView: UICollectionView) {
            self.dataSource = UICollectionViewDiffableDataSource<Int, String>(
                collectionView: collectionView
            ) { [weak self] collectionView, indexPath, identifier in
                self?.cellProvider(collectionView: collectionView, indexPath: indexPath, identifier: identifier) ?? UICollectionViewCell()
            }
        }
        
        private func cellProvider(collectionView: UICollectionView, indexPath: IndexPath, identifier: String) -> UICollectionViewCell {
            let columns = self.availableColumns[self.currentColumnIndex]
            
            if columns == 1 {
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: PhotoFullscreenCell.reuseIdentifier,
                    for: indexPath
                ) as? PhotoFullscreenCell else {
                    return UICollectionViewCell()
                }

                guard indexPath.item < self.sortedAssets.count else { return cell }
                let asset = self.sortedAssets[indexPath.item]
                let assetID = asset.localIdentifier
                
                let targetSize = CGSize(width: 1200, height: 1200)
                
                cell.configure(
                    with: asset,
                    imageManager: self.imageManager,
                    targetSize: targetSize
                )
                
                cell.onFaceTapped = { [weak self] observation, image, faceIndex in
                    self?.handleFaceTapped(observation: observation, image: image, asset: asset, faceIndex: faceIndex)
                }
                
                cell.onPhotoTapped = { [weak self] in
                    self?.zoomOutFromFullscreen()
                }
                
                cell.onPhotoLongPress = { [weak self] asset in
                    self?.handlePhotoLongPress(asset: asset)
                }
                
                cell.onFacesDetected = { [weak self] image, observations, detectedAssetID in
                    guard let self = self else { return }
                    guard detectedAssetID == assetID else {
                        print("⚠️ [PhotoGrid] Ignoring stale face detection for \(detectedAssetID), current asset is \(assetID)")
                        return
                    }
                    self.handleFacesDetectedInCell(image: image, observations: observations, fromIndex: indexPath.item)
                }

                return cell
            } else {
                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: PhotoCell.reuseIdentifier,
                    for: indexPath
                ) as? PhotoCell else {
                    return UICollectionViewCell()
                }

                guard indexPath.item < self.sortedAssets.count else { return cell }
                let asset = self.sortedAssets[indexPath.item]
                
                let cellSize = self.cellSizeForCurrentColumns()
                let targetSize = self.optimalTargetSize(for: cellSize)

                cell.configure(
                    with: asset,
                    imageManager: self.imageManager,
                    cache: self.imageCache,
                    targetSize: targetSize
                )

                return cell
            }
        }

        func updateAssets(_ newAssets: [PHAsset], initialScrollDate: Date?) {
            // Don't update if we're dismissing
            if isPreparedForDismissal {
                return
            }
            
            if isZooming {
                return
            }

            // Filter out deleted assets and sort by date ASCENDING (oldest first, newest at bottom)
            let validAssets = newAssets.filter { !deletedAssetIDs.contains($0.localIdentifier) }
            sortedAssets = validAssets.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

            if !hasPerformedInitialScroll && initialScrollDate != nil {
                pendingScrollDate = initialScrollDate
            }

            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(sortedAssets.map { $0.localIdentifier }, toSection: 0)

            let shouldScrollToDate = !hasPerformedInitialScroll && pendingScrollDate != nil && !sortedAssets.isEmpty
            let shouldScrollToBottom = !hasPerformedInitialScroll && !sortedAssets.isEmpty && initialScrollDate == nil

            dataSource?.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self = self else { return }
                guard let collectionView = self.collectionView else { return }

                self.updateFloatingHeader()

                if shouldScrollToDate, let scrollDate = self.pendingScrollDate {
                    self.scrollToDate(scrollDate)
                    self.hasPerformedInitialScroll = true
                    self.pendingScrollDate = nil
                } else if shouldScrollToBottom {
                    // Perform layout immediately
                    collectionView.performBatchUpdates(nil) { _ in
                        // After batch updates complete, layout is guaranteed to be calculated
                        let lastIndex = self.sortedAssets.count - 1
                        let indexPath = IndexPath(item: lastIndex, section: 0)
                        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: false)
                        self.hasPerformedInitialScroll = true
                        
                        print("📍 [PhotoGrid] Scrolled to bottom after performBatchUpdates - index \(lastIndex)")
                    }
                }
            }
        }

        private func scrollToBottomSynchronously() {
            guard let collectionView = collectionView else { return }
            guard !sortedAssets.isEmpty else { return }
            
            // Schedule scroll for the next run loop iteration after layout is complete
            DispatchQueue.main.async {
                // Force layout calculation
                collectionView.layoutIfNeeded()
                
                // Now layout is complete, calculate bottom offset
                let contentHeight = collectionView.contentSize.height
                let boundsHeight = collectionView.bounds.height
                let contentInsets = collectionView.adjustedContentInset
                
                let maxOffsetY = max(0, contentHeight - boundsHeight + contentInsets.bottom)
                
                print("📍 [PhotoGrid] Scrolling to bottom - contentHeight: \(contentHeight), boundsHeight: \(boundsHeight), offset: \(maxOffsetY)")
                
                // Set content offset directly
                collectionView.setContentOffset(CGPoint(x: 0, y: maxOffsetY), animated: false)
            }
        }
        
        private func scrollToBottom() {
            guard let collectionView = collectionView else { return }
            guard !sortedAssets.isEmpty else { return }
            
            let lastIndex = sortedAssets.count - 1
            let indexPath = IndexPath(item: lastIndex, section: 0)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                collectionView.scrollToItem(at: indexPath, at: .bottom, animated: false)
            }
        }

        private func scrollToDate(_ date: Date) {
            guard let collectionView = collectionView else { return }
            guard !sortedAssets.isEmpty else { return }

            var closestIndex = 0
            var closestDiff: TimeInterval = .infinity

            for (index, asset) in sortedAssets.enumerated() {
                if let assetDate = asset.creationDate {
                    let diff = abs(assetDate.timeIntervalSince(date))
                    if diff < closestDiff {
                        closestDiff = diff
                        closestIndex = index
                    }
                }
            }

            let indexPath = IndexPath(item: closestIndex, section: 0)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
            }
        }

        func cleanup() {
            imageManager.stopCachingImagesForAllAssets()
            
            if let hosting = carouselHostingController {
                hosting.willMove(toParent: nil)
                hosting.view.removeFromSuperview()
                hosting.removeFromParent()
                carouselHostingController = nil
            }
        }

        private func updateFloatingHeader() {
            guard let collectionView = collectionView,
                  let floatingHeader = floatingHeader else { return }

            let centerPoint = CGPoint(
                x: collectionView.bounds.midX,
                y: collectionView.contentOffset.y + 100
            )

            if let indexPath = collectionView.indexPathForItem(at: centerPoint),
               indexPath.item < sortedAssets.count {
                let asset = sortedAssets[indexPath.item]
                floatingHeader.configure(with: asset.creationDate)
                floatingHeader.alpha = availableColumns[currentColumnIndex] != 1 ? 1.0 : 0.0
            } else if !sortedAssets.isEmpty {
                floatingHeader.configure(with: sortedAssets[0].creationDate)
                floatingHeader.alpha = availableColumns[currentColumnIndex] != 1 ? 1.0 : 0.0
            } else {
                floatingHeader.alpha = 0.0
            }
        }

        private func optimalTargetSize(for cellSize: CGFloat) -> CGSize {
            let scale = UIScreen.main.scale
            let columns = availableColumns[currentColumnIndex]
            
            let targetPixels: CGFloat
            
            switch columns {
            case 1:
                targetPixels = 1200
            case 3:
                targetPixels = 600
            case 5:
                targetPixels = 400
            default:
                targetPixels = 400
            }
            
            return CGSize(width: targetPixels, height: targetPixels)
        }

        // MARK: - Face Handling

        private func handleFaceTapped(observation: VNFaceObservation, image: UIImage, asset: PHAsset, faceIndex: Int) {
            guard let cgImage = image.cgImage else { return }
            
            let imageSize = CGSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            let faceRect = FaceCrop.expandedRect(for: observation, imageSize: imageSize)
            
            if let cropped = cgImage.cropping(to: faceRect) {
                let faceImage = UIImage(cgImage: cropped)
                onPhotoTapped(faceImage, asset.creationDate)
            }
        }
        
        private func handlePhotoLongPress(asset: PHAsset) {
            let alert = UIAlertController(
                title: nil,
                message: "Hide this photo?",
                preferredStyle: .actionSheet
            )
            
            alert.addAction(UIAlertAction(title: "Hide Photo", style: .destructive) { [weak self] _ in
                self?.hideAsset(asset)
            })
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = scene.windows.first,
               let rootVC = window.rootViewController {
                
                var presentingVC = rootVC
                while let presented = presentingVC.presentedViewController {
                    presentingVC = presented
                }
                
                presentingVC.present(alert, animated: true)
            }
        }
        
        private func handleFacesDetectedInCell(image: UIImage, observations: [VNFaceObservation], fromIndex: Int) {
            // Only process faces from the currently visible/centered fullscreen item
            guard availableColumns[currentColumnIndex] == 1 else {
                print("⚠️ [PhotoGrid] Ignoring face detection - not in fullscreen mode")
                return
            }
            
            // Get the currently centered index
            let centeredIndex = getCenterVisibleItemIndex()
            
            guard fromIndex == centeredIndex else {
                print("⚠️ [PhotoGrid] Ignoring face detection from index \(fromIndex), centered index is \(centeredIndex ?? -1)")
                return
            }
            
            print("✅ [PhotoGrid] Processing face detection from centered index \(fromIndex)")
            
            guard !observations.isEmpty else {
                Task { @MainActor in
                    self.hideCarousel()
                }
                return
            }
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.currentFaceViewModel.detectFaces(in: image)
                
                self.faceDetectionViewModelSetter(self.currentFaceViewModel)
                
                self.setupCarousel(with: self.currentFaceViewModel)
            }
        }
        
        private func updateCurrentVisibleFullscreenIndex() {
            guard availableColumns[currentColumnIndex] == 1 else {
                currentVisibleFullscreenIndex = nil
                return
            }
            
            currentVisibleFullscreenIndex = getCenterVisibleItemIndex()
            print("📍 [PhotoGrid] Current visible fullscreen index: \(currentVisibleFullscreenIndex ?? -1)")
        }
        
        private func hideAsset(_ asset: PHAsset) {
            let assetID = asset.localIdentifier
            deletedAssetIDs.insert(assetID)
            
            // Remove from sorted assets
            sortedAssets.removeAll { $0.localIdentifier == assetID }
            
            // Update snapshot
            var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
            snapshot.appendSections([0])
            snapshot.appendItems(sortedAssets.map { $0.localIdentifier }, toSection: 0)
            
            dataSource?.apply(snapshot, animatingDifferences: true) { [weak self] in
                if self?.availableColumns[self?.currentColumnIndex ?? 0] == 1 {
                    self?.zoomOutFromFullscreen()
                }
            }
        }

        // MARK: - Zoom Controls

        private func zoomOutFromFullscreen() {
            let targetColumnIndex = 1 // Back to 3 columns
            guard targetColumnIndex != currentColumnIndex else { return }
            
            guard let collectionView = collectionView else { return }
            
            // Get center visible item
            let centerIndex = getCenterVisibleItemIndex()
            
            currentColumnIndex = targetColumnIndex
            
            CATransaction.begin()
            CATransaction.setDisableActions(false)
            CATransaction.setAnimationDuration(0.35)
            
            updateScrollBehavior()
            compositionalLayout?.invalidateLayout()
            collectionView.layoutIfNeeded()
            
            if let centerIndex = centerIndex {
                let indexPath = IndexPath(item: centerIndex, section: 0)
                collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
            }
            
            CATransaction.commit()

            if let snapshot = dataSource?.snapshot() {
                dataSource?.apply(snapshot, animatingDifferences: false)
            }
        }
        
        private func getCenterVisibleItemIndex() -> Int? {
            guard let collectionView = collectionView else { return nil }
            
            let centerPoint = CGPoint(
                x: collectionView.bounds.midX,
                y: collectionView.contentOffset.y + collectionView.bounds.height / 2
            )
            
            if let indexPath = collectionView.indexPathForItem(at: centerPoint) {
                return indexPath.item
            }
            
            return collectionView.indexPathsForVisibleItems.sorted().first?.item
        }

        // MARK: - Pinch-to-Zoom

        func installPinchGesture(on collectionView: UICollectionView) {
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            collectionView.addGestureRecognizer(pinch)
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let collectionView = collectionView else { return }

            switch gesture.state {
            case .began:
                isZooming = true
                onDetailVisibilityChanged(true)
                
                // Get the item under the pinch gesture, not the center item
                let pinchLocation = gesture.location(in: collectionView)
                if let indexPath = collectionView.indexPathForItem(at: pinchLocation) {
                    anchorIndex = indexPath.item
                    print("📍 [Pinch] Anchor set to item \(indexPath.item) at pinch location")
                } else {
                    // Fallback to center if pinch location doesn't hit an item
                    anchorIndex = getCenterVisibleItemIndex()
                    print("📍 [Pinch] Fallback to center item")
                }

            case .changed:
                guard let anchor = anchorIndex else { return }
                
                let scale = gesture.scale
                
                var targetColumnIndex: Int
                if scale > 1.2 {
                    // Pinching out = zoom in = fewer columns
                    targetColumnIndex = max(0, currentColumnIndex - 1)
                } else if scale < 0.8 {
                    // Pinching in = zoom out = more columns
                    targetColumnIndex = min(availableColumns.count - 1, currentColumnIndex + 1)
                } else {
                    return
                }
                
                guard targetColumnIndex != currentColumnIndex else { return }
                guard anchor < sortedAssets.count else { return }
                
                print("🔄 [Pinch] Zoom: \(availableColumns[currentColumnIndex]) → \(availableColumns[targetColumnIndex]) columns on item \(anchor)")
                
                currentColumnIndex = targetColumnIndex
                
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                
                UIView.performWithoutAnimation {
                    self.updateScrollBehavior()
                    self.compositionalLayout?.invalidateLayout()
                    collectionView.layoutIfNeeded()
                    
                    let indexPath = IndexPath(item: anchor, section: 0)
                    collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
                    
                    if let snapshot = self.dataSource?.snapshot() {
                        self.dataSource?.apply(snapshot, animatingDifferences: false)
                    }
                }
                
                CATransaction.commit()
                
                gesture.scale = 1.0

            case .ended, .cancelled, .failed:
                print("📍 [Pinch] Ended at \(availableColumns[currentColumnIndex]) columns")
                anchorIndex = nil
                isZooming = false
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, !self.isZooming else { return }
                    self.onDetailVisibilityChanged(false)
                }

            default:
                break
            }
        }
        
        func prepareForDismissal() {
            isPreparedForDismissal = true
            
            // Immediately hide carousel without animation
            carouselContainer?.alpha = 0
            
            // Clean up face detection
            Task { @MainActor in
                self.currentFaceViewModel.faces = []
            }
        }
    }
}

// MARK: - UICollectionViewDelegate

extension PhotoGridView.Coordinator: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        Task { @MainActor in
            onAppearAtIndex(indexPath.item)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let columns = availableColumns[currentColumnIndex]
        
        if columns == 1 {
            return
        }
        
        anchorIndex = indexPath.item
        currentColumnIndex = 0 // Zoom to fullscreen
        
        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setAnimationDuration(0.35)
        
        updateScrollBehavior()
        compositionalLayout?.invalidateLayout()
        collectionView.layoutIfNeeded()
        
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        
        CATransaction.commit()
        
        if let snapshot = dataSource?.snapshot() {
            dataSource?.apply(snapshot, animatingDifferences: false)
        }
    }
}

// MARK: - UICollectionViewDataSourcePrefetching

extension PhotoGridView.Coordinator: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let cellSize = cellSizeForCurrentColumns()
        let targetSize = optimalTargetSize(for: cellSize)

        let assetsToCache = indexPaths.prefix(50).compactMap { indexPath -> PHAsset? in
            guard indexPath.item < sortedAssets.count else { return nil }
            let asset = sortedAssets[indexPath.item]

            let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
            if imageCache.image(for: cacheKey) != nil {
                return nil
            }

            return asset
        }

        guard !assetsToCache.isEmpty else { return }

        imageManager.startCachingImages(
            for: Array(assetsToCache),
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let cellSize = cellSizeForCurrentColumns()
        let targetSize = optimalTargetSize(for: cellSize)

        let assetsToStop = indexPaths.compactMap { indexPath -> PHAsset? in
            guard indexPath.item < sortedAssets.count else { return nil }
            return sortedAssets[indexPath.item]
        }

        guard !assetsToStop.isEmpty else { return }

        imageManager.stopCachingImages(
            for: Array(assetsToStop),
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }
}

// MARK: - UIScrollViewDelegate

extension PhotoGridView.Coordinator: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFloatingHeader()
        
        // In fullscreen mode, update which item is centered and trigger face detection
        if availableColumns[currentColumnIndex] == 1 {
            let newCenteredIndex = getCenterVisibleItemIndex()
            
            if newCenteredIndex != currentVisibleFullscreenIndex {
                print("📍 [PhotoGrid] Centered index changed: \(currentVisibleFullscreenIndex ?? -1) → \(newCenteredIndex ?? -1)")
                currentVisibleFullscreenIndex = newCenteredIndex
                
                // Clear faces temporarily while scrolling to new item
                Task { @MainActor in
                    self.currentFaceViewModel.faces = []
                }
            }
        }
    }
    
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // Only snap in fullscreen mode
        guard availableColumns[currentColumnIndex] == 1 else { return }
        guard let collectionView = collectionView else { return }
        
        let targetY = targetContentOffset.pointee.y
        let centerY = targetY + collectionView.bounds.height / 2
        
        // Find the item closest to the target center point
        let targetPoint = CGPoint(x: collectionView.bounds.midX, y: centerY)
        
        if let indexPath = collectionView.indexPathForItem(at: targetPoint),
           let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
            // Snap to center this item
            let itemCenterY = attributes.frame.midY
            let newTargetY = itemCenterY - collectionView.bounds.height / 2
            
            // Clamp to valid content offset range
            let maxY = max(0, collectionView.contentSize.height - collectionView.bounds.height)
            targetContentOffset.pointee.y = max(0, min(newTargetY, maxY))
            
            print("📍 [Snap] Snapping to item \(indexPath.item) at offset \(targetContentOffset.pointee.y)")
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // When scroll settles in fullscreen, ensure we have the correct faces
        if availableColumns[currentColumnIndex] == 1 {
            updateCurrentVisibleFullscreenIndex()
            
            // Trigger re-detection for the centered cell
            if let centeredIndex = currentVisibleFullscreenIndex,
               let collectionView = collectionView,
               centeredIndex < sortedAssets.count {
                let indexPath = IndexPath(item: centeredIndex, section: 0)
                
                // Force the cell to re-detect faces
                if let cell = collectionView.cellForItem(at: indexPath) as? PhotoFullscreenCell {
                    print("🔄 [PhotoGrid] Re-triggering face detection for settled item at index \(centeredIndex)")
                    // The cell will automatically detect faces when it loads the image
                }
            }
        }
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        // If not decelerating, we've settled immediately
        if !decelerate && availableColumns[currentColumnIndex] == 1 {
            updateCurrentVisibleFullscreenIndex()
        }
    }
}

// MARK: - Floating Date Header View

final class FloatingDateHeaderView: UIView {
    private let label = UILabel()
    private let containerView = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)
        
        blurView.layer.cornerRadius = 10
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(blurView)
        
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.1
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowRadius = 4
        
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(label)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            blurView.topAnchor.constraint(equalTo: containerView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            label.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -6)
        ])
    }

    func configure(with date: Date?) {
        guard let date = date else {
            label.text = "Photos"
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        label.text = formatter.string(from: date)
    }
}

// MARK: - Photo Cell

final class PhotoCell: UICollectionViewCell {
    static let reuseIdentifier = "PhotoCell"

    private let imageView = UIImageView()
    private var currentRequestID: PHImageRequestID?
    private var representedAssetIdentifier: String?
    private var currentCacheKey: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        contentView.backgroundColor = UIColor.secondarySystemGroupedBackground
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        if let requestID = currentRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            currentRequestID = nil
        }

        representedAssetIdentifier = nil
        currentCacheKey = nil
        imageView.image = nil
    }

    func configure(with asset: PHAsset, imageManager: PHCachingImageManager, cache: ImageCacheService, targetSize: CGSize) {
        let assetIdentifier = asset.localIdentifier
        representedAssetIdentifier = assetIdentifier

        let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
        currentCacheKey = cacheKey

        if let cachedImage = cache.image(for: cacheKey) {
            imageView.image = cachedImage
            return
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        currentRequestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, info in
            guard let self = self else { return }

            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            guard !isCancelled else { return }

            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false

            guard self.representedAssetIdentifier == assetIdentifier,
                  self.currentCacheKey == cacheKey else {
                return
            }

            if let image = image {
                self.imageView.image = image

                if !isDegraded {
                    cache.setImage(image, for: cacheKey)
                }
            }
        }
    }
}