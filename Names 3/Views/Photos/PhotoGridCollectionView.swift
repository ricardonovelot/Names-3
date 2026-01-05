import SwiftUI
import UIKit
import Photos
import SwiftData

// MARK: - PhotoGridView

struct PhotoGridView: UIViewRepresentable {
    let assets: [PHAsset]
    let imageManager: PHCachingImageManager
    let contactsContext: ModelContext
    let initialScrollDate: Date?
    let onPhotoTapped: (UIImage, Date?) -> Void
    let onAppearAtIndex: (Int) -> Void
    let onDetailVisibilityChanged: (Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        print("🔵 [PhotoGridView] makeUIView called - creating new view hierarchy")
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

        context.coordinator.configureDataSource(for: collectionView)

        let floatingHeader = MonthHeaderView(frame: .zero)
        floatingHeader.translatesAutoresizingMaskIntoConstraints = false

        containerView.addSubview(collectionView)
        containerView.addSubview(floatingHeader)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: containerView.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            floatingHeader.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            floatingHeader.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            floatingHeader.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            floatingHeader.heightAnchor.constraint(equalToConstant: 44)
        ])

        context.coordinator.collectionView = collectionView
        context.coordinator.floatingHeader = floatingHeader
        context.coordinator.containerView = containerView
        context.coordinator.installPinchGesture(on: collectionView)

        print("✅ [PhotoGridView] makeUIView complete - collection view configured")
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        print("🔵 [PhotoGridView] updateUIView called")
        print("📍 [PhotoGridView] UIView alpha: \(uiView.alpha), hidden: \(uiView.isHidden)")
        print("📍 [PhotoGridView] UIView frame: \(uiView.frame)")
        print("📍 [PhotoGridView] UIView bounds: \(uiView.bounds)")
        print("📍 [PhotoGridView] UIView superview: \(uiView.superview != nil)")
        print("📍 [PhotoGridView] UIView subviews count: \(uiView.subviews.count)")
        if let collectionView = context.coordinator.collectionView {
            print("📍 [PhotoGridView] CollectionView frame: \(collectionView.frame)")
            print("📍 [PhotoGridView] CollectionView alpha: \(collectionView.alpha)")
            print("📍 [PhotoGridView] CollectionView hidden: \(collectionView.isHidden)")
            print("📍 [PhotoGridView] CollectionView visible cells: \(collectionView.visibleCells.count)")
        }
        print("📍 [PhotoGridView] Coordinator isTransitioning: \(context.coordinator.isTransitioning)")

        uiView.alpha = 1.0
        uiView.isHidden = false
        if let collectionView = context.coordinator.collectionView {
            collectionView.alpha = 1.0
            collectionView.isHidden = false
        }

        context.coordinator.updateAssets(assets, initialScrollDate: initialScrollDate)

        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        print("📍 [PhotoGridView] updateUIView complete")
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        print("🔴 [PhotoGridView] dismantleUIView called - view is being destroyed!")
        print("🔴 [PhotoGridView] isTransitioning: \(coordinator.isTransitioning)")
        
        if coordinator.isTransitioning {
            print("⚠️ [PhotoGridView] View being destroyed during transition - forcing restoration")
            coordinator.restoreScrollPosition()
        }
        
        print("🔴 [PhotoGridView] Stack trace:")
        Thread.callStackSymbols.prefix(10).forEach { print("  \($0)") }
        coordinator.cleanup()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            imageManager: imageManager,
            contactsContext: contactsContext,
            onPhotoTapped: onPhotoTapped,
            onAppearAtIndex: onAppearAtIndex,
            onDetailVisibilityChanged: onDetailVisibilityChanged
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let imageManager: PHCachingImageManager
        let contactsContext: ModelContext
        let onPhotoTapped: (UIImage, Date?) -> Void
        let onAppearAtIndex: (Int) -> Void
        let onDetailVisibilityChanged: (Bool) -> Void

        weak var collectionView: UICollectionView?
        weak var floatingHeader: MonthHeaderView?
        weak var containerView: UIView?

        private var dataSource: UICollectionViewDiffableDataSource<MonthSection, String>?
        private var assetsByID: [String: PHAsset] = [:]
        private var sections: [MonthSection] = []
        private var hasPerformedInitialScroll = false
        private var pendingScrollDate: Date?
        private var isWaitingForMoreAssets = false

        private let imageCache = ImageCacheService.shared

        // Compositional layout state
        private(set) var compositionalLayout: UICollectionViewCompositionalLayout?
        private let itemSpacing: CGFloat = 1
        private let sectionInsets = NSDirectionalEdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
        private var zoomScale: CGFloat = 1.0

        // Zoom tunables and pinch anchoring state
        private let zoomGain: CGFloat = 1.6
        private let minZoomScale: CGFloat = 0.5
        private let maxZoomScale: CGFloat = 6.0
        private let baseCellWidth: CGFloat = 120

        // Grid pinch-to-zoom state
        private var pinchStartZoomScale: CGFloat = 1.0
        private var pinchStartOffset: CGPoint = .zero
        private var pinchStartLocationInCV: CGPoint = .zero
        private var pinchStartIndexPath: IndexPath?
        private var pinchStartOffsetInCell: CGPoint = .zero
        private var pinchStartContentSize: CGSize = .zero

        // More anchoring state to improve stability during zoom-out
        private var pinchStartCellSide: CGFloat = 0
        private var pinchStartInset: UIEdgeInsets = .zero

        // private var transitionDelegate: PhotoZoomTransitionDelegate?
        private var selectedIndexPath: IndexPath?
        private var scrollPositionBeforeDetail: CGPoint?

        // Transition/update guards
        var isTransitioning: Bool = false
        private var lastAppliedAssetCount: Int = 0
        private var lastRestorationTime: Date?

        init(imageManager: PHCachingImageManager, contactsContext: ModelContext, onPhotoTapped: @escaping (UIImage, Date?) -> Void, onAppearAtIndex: @escaping (Int) -> Void, onDetailVisibilityChanged: @escaping (Bool) -> Void) {
            self.imageManager = imageManager
            self.contactsContext = contactsContext
            self.onPhotoTapped = onPhotoTapped
            self.onAppearAtIndex = onAppearAtIndex
            self.onDetailVisibilityChanged = onDetailVisibilityChanged
            super.init()
        }

        func makeCompositionalLayout() -> UICollectionViewCompositionalLayout {
            let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
                guard let self = self else { return nil }

                let containerWidth = environment.container.contentSize.width
                let availableWidth = max(0, containerWidth - self.sectionInsets.leading - self.sectionInsets.trailing)

                let columns = self.computeColumns(availableWidth: availableWidth)
                let cellSide = self.computeCellSide(availableWidth: availableWidth, columns: columns)

                let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(cellSide), heightDimension: .absolute(cellSide))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)

                let groupSize = NSCollectionLayoutSize(widthDimension: .absolute(availableWidth), heightDimension: .absolute(cellSide))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: columns)
                group.interItemSpacing = .fixed(self.itemSpacing)

                let section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = self.itemSpacing
                section.contentInsets = self.sectionInsets
                return section
            }
            self.compositionalLayout = layout
            return layout
        }

        private func computeColumns(availableWidth: CGFloat) -> Int {
            let desiredCell = max(40, baseCellWidth * max(zoomScale, 0.01))
            let columns = Int(floor((availableWidth + itemSpacing) / (desiredCell + itemSpacing)))
            return max(1, min(40, columns))
        }

        private func computeCellSide(availableWidth: CGFloat, columns: Int) -> CGFloat {
            guard columns > 0 else { return 40 }
            let totalSpacing = CGFloat(columns - 1) * itemSpacing
            return max(40, floor((availableWidth - totalSpacing) / CGFloat(columns)))
        }

        private func currentCellSide() -> CGFloat {
            guard let collectionView = collectionView else { return baseCellWidth }
            let availableWidth = max(0, collectionView.bounds.width - sectionInsets.leading - sectionInsets.trailing)
            let columns = computeColumns(availableWidth: availableWidth)
            return computeCellSide(availableWidth: availableWidth, columns: columns)
        }

        func configureDataSource(for collectionView: UICollectionView) {
            dataSource = UICollectionViewDiffableDataSource<MonthSection, String>(
                collectionView: collectionView
            ) { [weak self] collectionView, indexPath, identifier in
                guard let self = self else { return UICollectionViewCell() }

                guard let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: PhotoCell.reuseIdentifier,
                    for: indexPath
                ) as? PhotoCell else {
                    return UICollectionViewCell()
                }

                if let asset = self.assetsByID[identifier] {
                    let cellSize = self.currentCellSide()
                    let targetSize = self.optimalTargetSize(for: cellSize)

                    cell.configure(
                        with: asset,
                        imageManager: self.imageManager,
                        cache: self.imageCache,
                        targetSize: targetSize
                    )
                }

                return cell
            }
        }

        func updateAssets(_ newAssets: [PHAsset], initialScrollDate: Date?) {
            if isTransitioning {
                print("⏸️ [PhotoGrid] Skipping update - transition in progress")
                return
            }

            if let lastRestore = lastRestorationTime,
               Date().timeIntervalSince(lastRestore) < 1.0,
               newAssets.count == lastAppliedAssetCount {
                print("⏸️ [PhotoGrid] Skipping redundant update after restoration - same asset count (\(newAssets.count))")
                return
            }

            let previousOffset = collectionView?.contentOffset

            print("🔵 [PhotoGrid] updateAssets called with \(newAssets.count) assets")
            print("📍 [PhotoGrid] Current offset: \(previousOffset?.debugDescription ?? "nil")")

            var assetsByMonth: [MonthSection: [PHAsset]] = [:]
            var seenIDs = Set<String>()

            for asset in newAssets {
                let id = asset.localIdentifier
                guard seenIDs.insert(id).inserted else { continue }

                assetsByID[id] = asset

                guard let creationDate = asset.creationDate else { continue }
                let monthDate = monthStart(for: creationDate)
                let section = MonthSection(date: monthDate)

                assetsByMonth[section, default: []].append(asset)
            }

            sections = assetsByMonth.keys.sorted { $0.date > $1.date }

            var snapshot = NSDiffableDataSourceSnapshot<MonthSection, String>()

            for section in sections {
                snapshot.appendSections([section])

                if let assetsInSection = assetsByMonth[section] {
                    let sortedAssets = assetsInSection.sorted {
                        ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
                    }
                    let ids = sortedAssets.map { $0.localIdentifier }
                    snapshot.appendItems(ids, toSection: section)
                }
            }

            if !hasPerformedInitialScroll && initialScrollDate != nil {
                pendingScrollDate = initialScrollDate
                isWaitingForMoreAssets = true
            }

            let shouldAttemptScroll = !hasPerformedInitialScroll &&
                                      pendingScrollDate != nil &&
                                      !sections.isEmpty &&
                                      shouldScrollNow(targetDate: pendingScrollDate!)

            if shouldAttemptScroll {
                print("🔵 [PhotoGrid] Will perform initial scroll to date: \(pendingScrollDate!)")
                print("🔵 [PhotoGrid] Total sections: \(sections.count), Total assets: \(newAssets.count)")
            }

            dataSource?.apply(snapshot, animatingDifferences: false) { [weak self] in
                guard let self = self else { return }

                if let offset = previousOffset, !shouldAttemptScroll, self.hasPerformedInitialScroll {
                    print("📍 [PhotoGrid] Restoring scroll offset: \(offset)")
                    self.collectionView?.contentOffset = offset
                }

                self.updateFloatingHeader()

                if shouldAttemptScroll, let scrollDate = self.pendingScrollDate {
                    print("🔵 [PhotoGrid] Applying snapshot complete, performing scroll")
                    self.scrollToDate(scrollDate)
                    self.hasPerformedInitialScroll = true
                    self.pendingScrollDate = nil
                    self.isWaitingForMoreAssets = false
                }

                self.lastAppliedAssetCount = newAssets.count
            }
        }

        private func shouldScrollNow(targetDate: Date) -> Bool {
            guard !sections.isEmpty else { return false }

            let targetMonthStart = monthStart(for: targetDate)

            if sections.contains(where: { $0.date == targetMonthStart }) {
                print("✅ [PhotoGrid] Target month found in loaded sections")
                return true
            }

            let oldestSection = sections.max(by: { $0.date < $1.date })
            let newestSection = sections.min(by: { $0.date < $1.date })

            if let oldest = oldestSection?.date, let newest = newestSection?.date {
                let isInRange = targetDate >= oldest && targetDate <= newest
                print("🔵 [PhotoGrid] Target date range check - Oldest: \(oldest), Newest: \(newest), Target: \(targetDate), InRange: \(isInRange)")

                if isInRange {
                    print("✅ [PhotoGrid] Target date is within loaded range")
                    return true
                }
            }

            if sections.count > 10 {
                print("✅ [PhotoGrid] Enough sections loaded (\(sections.count)), proceeding with scroll")
                return true
            }

            print("⏳ [PhotoGrid] Waiting for more assets - current sections: \(sections.count)")
            return false
        }

        private func scrollToDate(_ date: Date) {
            guard let collectionView = collectionView else {
                print("❌ [PhotoGrid] No collectionView available for scrolling")
                return
            }

            print("🔵 [PhotoGrid] scrollToDate called for: \(date)")

            let targetMonthStart = monthStart(for: date)
            print("🔵 [PhotoGrid] Target month start: \(targetMonthStart)")
            print("🔵 [PhotoGrid] Available sections: \(sections.map { $0.date })")

            if let sectionIndex = sections.firstIndex(where: { $0.date == targetMonthStart }) {
                print("✅ [PhotoGrid] Found exact match at section \(sectionIndex)")

                guard let snapshot = dataSource?.snapshot() else {
                    print("❌ [PhotoGrid] No snapshot available")
                    return
                }

                let section = sections[sectionIndex]
                let items = snapshot.itemIdentifiers(inSection: section)

                var closestItemIndex = 0
                var closestDiff: TimeInterval = .infinity

                for (index, itemID) in items.enumerated() {
                    if let asset = assetsByID[itemID], let assetDate = asset.creationDate {
                        let diff = abs(assetDate.timeIntervalSince(date))
                        if diff < closestDiff {
                            closestDiff = diff
                            closestItemIndex = index
                        }
                    }
                }

                print("✅ [PhotoGrid] Found closest item at index \(closestItemIndex) within section")
                let indexPath = IndexPath(item: closestItemIndex, section: sectionIndex)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("🎯 [PhotoGrid] Scrolling to item \(closestItemIndex) in section \(sectionIndex)")
                    collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: true)
                }
            } else {
                print("⚠️ [PhotoGrid] No exact match, finding closest section")
                var closestSection: (index: Int, date: Date)?

                for (index, section) in sections.enumerated() {
                    if closestSection == nil {
                        closestSection = (index, section.date)
                    } else if let current = closestSection {
                        let currentDiff = abs(current.date.timeIntervalSince(date))
                        let sectionDiff = abs(section.date.timeIntervalSince(date))
                        if sectionDiff < currentDiff {
                            closestSection = (index, section.date)
                        }
                    }
                }

                if let closest = closestSection {
                    print("✅ [PhotoGrid] Found closest section at index \(closest.index) with date \(closest.date)")
                    let indexPath = IndexPath(item: 0, section: closest.index)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("🎯 [PhotoGrid] Scrolling to closest section \(closest.index)")
                        collectionView.scrollToItem(at: indexPath, at: .top, animated: true)
                    }
                } else {
                    print("❌ [PhotoGrid] Could not find any section to scroll to")
                }
            }
        }

        func cleanup() {
            imageManager.stopCachingImagesForAllAssets()
        }

        private func updateFloatingHeader() {
            guard let collectionView = collectionView,
                  let floatingHeader = floatingHeader else { return }

            let visibleRect = CGRect(
                x: collectionView.contentOffset.x,
                y: collectionView.contentOffset.y,
                width: collectionView.bounds.width,
                height: collectionView.bounds.height
            )

            let centerPoint = CGPoint(
                x: visibleRect.midX,
                y: visibleRect.minY + 100
            )

            if let indexPath = collectionView.indexPathForItem(at: centerPoint),
               indexPath.section < sections.count {
                let section = sections[indexPath.section]
                floatingHeader.configure(with: section.date)
                floatingHeader.alpha = 1.0
            } else if !sections.isEmpty {
                let section = sections[0]
                floatingHeader.configure(with: section.date)
                floatingHeader.alpha = 1.0
            } else {
                floatingHeader.alpha = 0.0
            }
        }

        private func optimalTargetSize(for cellSize: CGFloat) -> CGSize {
            let scale = UIScreen.main.scale
            let pixelSize = cellSize * scale

            let targetPixels: CGFloat
            if pixelSize <= 120 {
                targetPixels = 120
            } else if pixelSize <= 180 {
                targetPixels = 180
            } else {
                targetPixels = 240
            }

            return CGSize(width: targetPixels, height: targetPixels)
        }

        private func monthStart(for date: Date) -> Date {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? date
        }

        private func globalIndexForIndexPath(_ indexPath: IndexPath) -> Int {
            guard let snapshot = dataSource?.snapshot() else { return 0 }

            var count = 0
            for (sectionIndex, section) in sections.enumerated() {
                if sectionIndex < indexPath.section {
                    count += snapshot.numberOfItems(inSection: section)
                } else {
                    count += indexPath.item
                    break
                }
            }
            return count
        }

        // MARK: - Pinch-to-zoom installation

        func installPinchGesture(on collectionView: UICollectionView) {
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.cancelsTouchesInView = false
            collectionView.addGestureRecognizer(pinch)
        }

        private func nearestIndexPath(to pointInCV: CGPoint) -> (IndexPath, UICollectionViewLayoutAttributes)? {
            guard let collectionView = collectionView else { return nil }
            let visible = collectionView.indexPathsForVisibleItems
            guard !visible.isEmpty else { return nil }
            var best: (IndexPath, UICollectionViewLayoutAttributes, CGFloat)?
            for ip in visible {
                if let attrs = collectionView.layoutAttributesForItem(at: ip) {
                    let center = CGPoint(x: attrs.frame.midX, y: attrs.frame.midY)
                    let dx = center.x - pointInCV.x
                    let dy = center.y - pointInCV.y
                    let d2 = dx*dx + dy*dy
                    if best == nil || d2 < best!.2 {
                        best = (ip, attrs, d2)
                    }
                }
            }
            if let b = best {
                return (b.0, b.1)
            }
            return nil
        }

        private func clampedOffset(for desired: CGPoint, contentSize: CGSize, inset: UIEdgeInsets, bounds: CGSize) -> CGPoint {
            let maxOffsetX = max(-inset.left, contentSize.width + inset.right - bounds.width)
            let maxOffsetY = max(-inset.top, contentSize.height + inset.bottom - bounds.height)
            let clampedX = min(max(desired.x, -inset.left), maxOffsetX)
            let clampedY = min(max(desired.y, -inset.top), maxOffsetY)
            return CGPoint(x: clampedX, y: clampedY)
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let collectionView = collectionView else { return }

            switch gesture.state {
            case .began:
                pinchStartZoomScale = zoomScale
                pinchStartOffset = collectionView.contentOffset
                pinchStartLocationInCV = gesture.location(in: collectionView)
                pinchStartContentSize = collectionView.collectionViewLayout.collectionViewContentSize
                pinchStartCellSide = currentCellSide()
                pinchStartInset = collectionView.contentInset

                collectionView.layoutIfNeeded()
                if let ip = collectionView.indexPathForItem(at: pinchStartLocationInCV),
                   let attrs = collectionView.layoutAttributesForItem(at: ip) {
                    pinchStartIndexPath = ip
                    let contentPoint = CGPoint(x: pinchStartLocationInCV.x + pinchStartOffset.x,
                                               y: pinchStartLocationInCV.y + pinchStartOffset.y)
                    pinchStartOffsetInCell = CGPoint(x: contentPoint.x - attrs.frame.origin.x,
                                                     y: contentPoint.y - attrs.frame.origin.y)
                } else if let nearest = nearestIndexPath(to: pinchStartLocationInCV) {
                    pinchStartIndexPath = nearest.0
                    let contentPoint = CGPoint(x: pinchStartLocationInCV.x + pinchStartOffset.x,
                                               y: pinchStartLocationInCV.y + pinchStartOffset.y)
                    pinchStartOffsetInCell = CGPoint(x: contentPoint.x - nearest.1.frame.origin.x,
                                                     y: contentPoint.y - nearest.1.frame.origin.y)
                } else {
                    pinchStartIndexPath = nil
                    pinchStartOffsetInCell = .zero
                }

            case .changed:
                let scaledAroundOne = 1 + zoomGain * (gesture.scale - 1)
                var newZoom = pinchStartZoomScale * scaledAroundOne
                newZoom = max(minZoomScale, min(newZoom, maxZoomScale))

                if newZoom != zoomScale {
                    zoomScale = newZoom
                    compositionalLayout?.invalidateLayout()
                    collectionView.collectionViewLayout.invalidateLayout()
                    collectionView.layoutIfNeeded()
                }

                let newContentSize = collectionView.collectionViewLayout.collectionViewContentSize
                let desiredOffset: CGPoint

                if let ip = pinchStartIndexPath,
                   let newAttrs = collectionView.layoutAttributesForItem(at: ip) {
                    let targetContentPoint = CGPoint(x: newAttrs.frame.origin.x + pinchStartOffsetInCell.x,
                                                     y: newAttrs.frame.origin.y + pinchStartOffsetInCell.y)
                    desiredOffset = CGPoint(x: targetContentPoint.x - pinchStartLocationInCV.x,
                                            y: targetContentPoint.y - pinchStartLocationInCV.y)
                } else {
                    let newCellSide = currentCellSide()
                    let ratio = pinchStartCellSide > 0 ? (newCellSide / pinchStartCellSide) : 1
                    let startContentPoint = CGPoint(x: pinchStartLocationInCV.x + pinchStartOffset.x,
                                                    y: pinchStartLocationInCV.y + pinchStartOffset.y)
                    let scaledPoint = CGPoint(x: startContentPoint.x * ratio,
                                              y: startContentPoint.y * ratio)
                    desiredOffset = CGPoint(x: scaledPoint.x - pinchStartLocationInCV.x,
                                            y: scaledPoint.y - pinchStartLocationInCV.y)
                }

                let clamped = clampedOffset(for: desiredOffset,
                                            contentSize: newContentSize,
                                            inset: collectionView.contentInset,
                                            bounds: collectionView.bounds.size)
                collectionView.contentOffset = clamped

            case .ended, .cancelled, .failed:
                let oldInset = collectionView.contentInset
                let newInset = computeCenteredInset(for: collectionView)
                if newInset != oldInset {
                    collectionView.contentInset = newInset
                    let deltaX = newInset.left - oldInset.left
                    let deltaY = newInset.top - oldInset.top
                    let adjusted = CGPoint(x: collectionView.contentOffset.x + deltaX,
                                           y: collectionView.contentOffset.y + deltaY)
                    let contentSize = collectionView.collectionViewLayout.collectionViewContentSize
                    let clamped = clampedOffset(for: adjusted,
                                                contentSize: contentSize,
                                                inset: newInset,
                                                bounds: collectionView.bounds.size)
                    collectionView.contentOffset = clamped
                }
            default:
                break
            }
        }

        private func computeCenteredInset(for collectionView: UICollectionView) -> UIEdgeInsets {
            let contentSize = collectionView.collectionViewLayout.collectionViewContentSize
            let bounds = collectionView.bounds.size
            let insetX = max((bounds.width - contentSize.width) / 2, 0)
            let insetY = max((bounds.height - contentSize.height) / 2, 0)
            return UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        }

        func restoreScrollPosition() {
            guard let collectionView = collectionView else {
                print("⚠️ [PhotoGrid] No collection view available")
                isTransitioning = false
                return
            }
            guard let saved = scrollPositionBeforeDetail else {
                print("⚠️ [PhotoGrid] No saved scroll position to restore")
                isTransitioning = false
                return
            }

            print("📍 [PhotoGrid] === RESTORATION START ===")
            print("📍 [PhotoGrid] Restoring scroll position: \(saved)")
            
            // Restore the scroll position
            collectionView.setContentOffset(saved, animated: false)
            collectionView.layoutIfNeeded()
            
            let afterOffset = collectionView.contentOffset
            print("📍 [PhotoGrid] Offset after restore: \(afterOffset)")
            print("📍 [PhotoGrid] Visible cells: \(collectionView.visibleCells.count)")

            isTransitioning = false
            scrollPositionBeforeDetail = nil
            lastRestorationTime = Date()

            print("✅ [PhotoGrid] === RESTORATION COMPLETE ===")
            
            // Notify that detail is gone
            onDetailVisibilityChanged(false)
        }
    }
}

// MARK: - UICollectionViewDelegate

extension PhotoGridView.Coordinator: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        let globalIndex = globalIndexForIndexPath(indexPath)
        Task { @MainActor in
            onAppearAtIndex(globalIndex)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        print("🔵 [PhotoGrid] didSelectItemAt - Section: \(indexPath.section), Item: \(indexPath.item)")

        guard indexPath.section < sections.count else {
            print("❌ [PhotoGrid] Section index out of bounds")
            return
        }

        let section = sections[indexPath.section]
        guard let snapshot = dataSource?.snapshot() else {
            print("❌ [PhotoGrid] No snapshot available")
            return
        }

        let items = snapshot.itemIdentifiers(inSection: section)
        guard indexPath.item < items.count else {
            print("❌ [PhotoGrid] Item index out of bounds")
            return
        }

        let identifier = items[indexPath.item]
        guard let asset = assetsByID[identifier] else {
            print("❌ [PhotoGrid] Asset not found")
            return
        }

        guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoCell else {
            print("⚠️ [PhotoGrid] Cell not visible, falling back to direct presentation")
            presentPhotoDetail(for: asset, originFrame: .zero, originImage: nil, at: indexPath)
            return
        }

        guard let window = collectionView.window,
              let cellFrame = cell.superview?.convert(cell.frame, to: window) else {
            print("⚠️ [PhotoGrid] Could not get cell frame in window coordinates")
            presentPhotoDetail(for: asset, originFrame: .zero, originImage: nil, at: indexPath)
            return
        }

        let cellImage = cell.imageView.image
        print("✅ [PhotoGrid] Presenting with origin frame: \(cellFrame)")

        presentPhotoDetail(for: asset, originFrame: cellFrame, originImage: cellImage, at: indexPath)
    }

    private func presentPhotoDetail(for asset: PHAsset, originFrame: CGRect, originImage: UIImage?, at indexPath: IndexPath) {
        selectedIndexPath = indexPath
        isTransitioning = true
        
        // Notify that detail is being shown to suppress reloads
        onDetailVisibilityChanged(true)

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        print("🔄 [PhotoGrid] Requesting full image for asset")
        imageManager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            guard let self = self else { return }

            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false

            guard !isDegraded, !isCancelled, let image = image else { return }

            print("✅ [PhotoGrid] Full quality image received")

            Task { @MainActor in
                guard let collectionView = self.collectionView else {
                    self.isTransitioning = false
                    self.onDetailVisibilityChanged(false)
                    return
                }
                
                self.scrollPositionBeforeDetail = collectionView.contentOffset
                print("📍 [PhotoGrid] Saved scroll position: \(self.scrollPositionBeforeDetail!)")
                
                // Notify parent to show detail via SwiftUI
                self.onPhotoTapped(image, asset.creationDate)
            }
        }
    }
}

// MARK: - UICollectionViewDataSourcePrefetching

extension PhotoGridView.Coordinator: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let cellSize = currentCellSide()
        let targetSize = optimalTargetSize(for: cellSize)

        let limitedPaths = Array(indexPaths.prefix(50))

        let assetsToCache = limitedPaths.compactMap { indexPath -> PHAsset? in
            guard indexPath.section < sections.count else { return nil }
            let section = sections[indexPath.section]

            guard let snapshot = dataSource?.snapshot() else { return nil }
            let items = snapshot.itemIdentifiers(inSection: section)
            guard indexPath.item < items.count else { return nil }

            let id = items[indexPath.item]
            guard let asset = assetsByID[id] else { return nil }

            let cacheKey = CacheKeyGenerator.key(for: asset, size: targetSize)
            if imageCache.image(for: cacheKey) != nil {
                return nil
            }

            return asset
        }

        guard !assetsToCache.isEmpty else { return }

        imageManager.startCachingImages(
            for: assetsToCache,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let cellSize = currentCellSide()
        let targetSize = optimalTargetSize(for: cellSize)

        let assetsToStop = indexPaths.compactMap { indexPath -> PHAsset? in
            guard indexPath.section < sections.count else { return nil }
            let section = sections[indexPath.section]

            guard let snapshot = dataSource?.snapshot() else { return nil }
            let items = snapshot.itemIdentifiers(inSection: section)
            guard indexPath.item < items.count else { return nil }

            let id = items[indexPath.item]
            return assetsByID[id]
        }

        guard !assetsToStop.isEmpty else { return }

        imageManager.stopCachingImages(
            for: assetsToStop,
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
    }
}

// MARK: - MonthSection

struct MonthSection: Hashable {
    let date: Date
}

// MARK: - Month Header View

final class MonthHeaderView: UIView {
    static let reuseIdentifier = "MonthHeaderView"

    private let label = UILabel()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        label.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(label)

        let trailing = label.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -16)
        trailing.priority = .defaultHigh
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            label.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 16),
            trailing,
            label.centerYAnchor.constraint(equalTo: blurView.contentView.centerYAnchor)
        ])
    }

    func configure(with date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        label.text = formatter.string(from: date)
    }
}

// MARK: - Photo Cell

final class PhotoCell: UICollectionViewCell {
    static let reuseIdentifier = "PhotoCell"

    let imageView = UIImageView()
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