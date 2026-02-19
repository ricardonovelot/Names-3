import SwiftUI
import UIKit

struct PagedCollectionView<Item, Content: View>: UIViewControllerRepresentable {
    let items: [Item]
    @Binding var index: Int
    /// When non-nil, the collection view starts at this index (no scroll). Used for Carousel→Feed bridge.
    var initialIndex: Int? = nil
    let id: (Item) -> String
    let onPrefetch: (IndexSet, CGSize) -> Void
    let onCancelPrefetch: (IndexSet, CGSize) -> Void
    let isPageReady: (Int) -> Bool
    let content: (Int, Item, Bool) -> Content

    let onScrollInteracting: (Bool) -> Void

    func makeUIViewController(context: Context) -> Controller {
        Diagnostics.log("PagedCollection makeUIViewController items=\(items.count) index=\(index)")
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        
        let vc = Controller(collectionViewLayout: layout)
        vc.collectionView.isPagingEnabled = true
        vc.collectionView.isPrefetchingEnabled = true
        vc.collectionView.showsVerticalScrollIndicator = false
        vc.collectionView.backgroundColor = .black
        vc.collectionView.dataSource = vc
        vc.collectionView.delegate = vc
        vc.collectionView.prefetchDataSource = vc
        vc.collectionView.register(Controller.Cell.self, forCellWithReuseIdentifier: "Cell")
        vc.indexBinding = self.$index
        vc.items = items
        vc.idProvider = id
        vc.onPrefetch = onPrefetch
        vc.onCancelPrefetch = onCancelPrefetch
        vc.isPageReady = isPageReady
        vc.contentBuilder = { idx, item, isActive in AnyView(content(idx, item, isActive)) }
        vc.captureIDs()
        vc.onScrollInteracting = onScrollInteracting
        vc.initialIndexOverride = initialIndex
        return vc
    }
    
    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        Diagnostics.log("PagedCollection updateUIViewController items=\(items.count) index=\(index)")
        uiViewController.indexBinding = self.$index
        uiViewController.initialIndexOverride = initialIndex
        uiViewController.contentBuilder = { idx, item, isActive in AnyView(content(idx, item, isActive)) }
        uiViewController.idProvider = id
        uiViewController.onPrefetch = onPrefetch
        uiViewController.onCancelPrefetch = onCancelPrefetch
        uiViewController.isPageReady = isPageReady
        uiViewController.onScrollInteracting = onScrollInteracting
        uiViewController.applyUpdates(items: items, index: index)
    }
    
    final class Controller: UICollectionViewController, UICollectionViewDataSourcePrefetching, UICollectionViewDelegateFlowLayout {
        var indexBinding: Binding<Int>!
        var initialIndexOverride: Int? = nil
        var items: [Item] = []
        var idProvider: ((Item) -> String)!
        var contentBuilder: ((Int, Item, Bool) -> AnyView)!
        var onPrefetch: ((IndexSet, CGSize) -> Void)!
        var onCancelPrefetch: ((IndexSet, CGSize) -> Void)!
        var isPageReady: ((Int) -> Bool)!
        var onScrollInteracting: ((Bool) -> Void)!
        
        private var didInitialScroll = false
        /// When we have initialIndexOverride but bounds=0, we can't scroll yet. Use this in viewDidLayoutSubviews.
        private var pendingBridgeTargetIndex: Int?
        /// When true, we own the index — block scrollViewDidScroll and commitPageChange from writing.
        private var isBridgeLockActive: Bool { pendingBridgeTargetIndex != nil }
        private var lastIDs: [String] = []
        private var prefetchedIndices: Set<Int> = []
        private let gateFraction: CGFloat = 0.2
        private var gateActive = false
        private lazy var gateSpinner: UIActivityIndicatorView = {
            let s = UIActivityIndicatorView(style: .large)
            s.hidesWhenStopped = true
            s.color = .white
            s.alpha = 0
            return s
        }()
        private var gateConstraintsInstalled = false
        
        func captureIDs() {
            lastIDs = items.map(idProvider)
        }

        /// Defer Binding writes to next run loop to avoid "Modifying state during view update" (applyUpdates is called from updateUIViewController).
        private func deferBindingWrite(_ block: @escaping () -> Void) {
            DispatchQueue.main.async(execute: block)
        }

        func applyUpdates(items: [Item], index: Int) {
            let newIDs = items.map(idProvider)
            let changed = newIDs != lastIDs
            let targetIdx = initialIndexOverride ?? index
            // #region agent log
            Diagnostics.debugBridge(hypothesisId: "H", location: "PagedCollection.applyUpdates", message: "applyUpdates", data: ["index": index, "targetIdx": targetIdx, "initialOverride": initialIndexOverride ?? -1, "itemsCount": items.count, "changed": changed, "boundsH": collectionView.bounds.height])
            // #endregion
            Diagnostics.log("PagedCollection applyUpdates changed=\(changed) items=\(items.count) targetIndex=\(targetIdx)")
            self.items = items

            if changed {
                lastIDs = newIDs
                collectionView.collectionViewLayout.invalidateLayout()
                collectionView.reloadData()
                prefetchedIndices = []
            }

            // Bridge: capture target whenever we have override and haven't scrolled yet (works even when changed=false)
            if let override = initialIndexOverride, items.indices.contains(override), !didInitialScroll {
                if collectionView.bounds.height > 0 {
                    collectionView.layoutIfNeeded()
                    setContentOffsetDirectly(to: override)
                    deferBindingWrite { self.indexBinding.wrappedValue = override }
                    didInitialScroll = true
                    pendingBridgeTargetIndex = nil
                } else {
                    pendingBridgeTargetIndex = override
                    deferBindingWrite { self.indexBinding.wrappedValue = override }
                }
            }

            let effectiveTarget = pendingBridgeTargetIndex ?? targetIdx
            if items.indices.contains(effectiveTarget) {
                let currentPage = computedPage()
                if currentPage != effectiveTarget, collectionView.bounds.height > 0 {
                    setContentOffsetDirectly(to: effectiveTarget)
                    deferBindingWrite { self.indexBinding.wrappedValue = effectiveTarget }
                    didInitialScroll = true
                    pendingBridgeTargetIndex = nil
                }
                refreshVisibleCellsActiveState()
                updatePrefetchWindow(for: effectiveTarget)
            }
        }

        /// Sets content offset directly without animation. Used for initial position.
        private func setContentOffsetDirectly(to index: Int) {
            guard items.indices.contains(index), collectionView.bounds.height > 0 else { return }
            collectionView.layoutIfNeeded()
            let offsetY = collectionView.bounds.height * CGFloat(index)
            collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
            Diagnostics.log("PagedCollection setContentOffsetDirectly index=\(index) offsetY=\(String(format: "%.1f", offsetY))")
        }
        
        override func viewDidLoad() {
            super.viewDidLoad()
            Diagnostics.log("PagedCollection Controller viewDidLoad")
            setupGateUI()
            onScrollInteracting?(false)
        }
        
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize = collectionView.bounds.size
            let targetIdx = pendingBridgeTargetIndex ?? initialIndexOverride ?? indexBinding.wrappedValue
            // #region agent log
            Diagnostics.debugBridge(hypothesisId: "I", location: "PagedCollection.viewDidLayoutSubviews", message: "viewDidLayoutSubviews", data: ["targetIdx": targetIdx, "initialOverride": initialIndexOverride ?? -1, "pendingBridge": pendingBridgeTargetIndex ?? -1, "boundsH": collectionView.bounds.height, "didInitialScroll": didInitialScroll, "itemsCount": items.count])
            // #endregion
            Diagnostics.log("PagedCollection viewDidLayoutSubviews size=\(NSCoder.string(for: collectionView.bounds.size)) didInitialScroll=\(didInitialScroll) pendingBridge=\(pendingBridgeTargetIndex?.description ?? "nil")")
            if !didInitialScroll, items.indices.contains(targetIdx), collectionView.bounds.height > 0 {
                setContentOffsetDirectly(to: targetIdx)
                didInitialScroll = true
                indexBinding.wrappedValue = targetIdx
                pendingBridgeTargetIndex = nil
                updatePrefetchWindow(for: targetIdx)
            }
            layoutGateUI()
        }
        
        private func setupGateUI() {
            guard gateSpinner.superview == nil else { return }
            collectionView.addSubview(gateSpinner)
            gateSpinner.translatesAutoresizingMaskIntoConstraints = false
            gateConstraintsInstalled = false
        }
        
        private func layoutGateUI() {
            guard !gateConstraintsInstalled else { return }
            gateConstraintsInstalled = true
            NSLayoutConstraint.activate([
                gateSpinner.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
                gateSpinner.bottomAnchor.constraint(equalTo: collectionView.safeAreaLayoutGuide.bottomAnchor, constant: -24)
            ])
        }
        
        private func showGateSpinner() {
            guard !gateActive else { return }
            gateActive = true
            Diagnostics.log("PagedCollection gateSpinner show")
            gateSpinner.startAnimating()
            UIView.animate(withDuration: 0.15) {
                self.gateSpinner.alpha = 1
            }
        }
        
        private func hideGateSpinner() {
            guard gateActive else { return }
            gateActive = false
            Diagnostics.log("PagedCollection gateSpinner hide")
            UIView.animate(withDuration: 0.15, animations: {
                self.gateSpinner.alpha = 0
            }, completion: { _ in
                if !self.gateActive {
                    self.gateSpinner.stopAnimating()
                }
            })
        }
        
        private func scrollTo(_ index: Int, animated: Bool) {
            guard items.indices.contains(index) else { return }
            let offsetY = collectionView.bounds.height * CGFloat(index)
            Diagnostics.log("PagedCollection scrollTo index=\(index) offsetY=\(String(format: "%.1f", offsetY)) animated=\(animated)")
            collectionView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: animated)
        }
        
        private func computedPage() -> Int {
            guard collectionView.bounds.height > 0 else { return indexBinding.wrappedValue }
            let page = Int(round(collectionView.contentOffset.y / collectionView.bounds.height))
            return max(0, min(items.count - 1, page))
        }
        
        override func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }
        override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            let c = items.count
            Diagnostics.log("PagedCollection numberOfItems=\(c)")
            return c
        }
        
        override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            Diagnostics.log("PagedCollection cellForItem idx=\(indexPath.item)")
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! Cell
            let item = items[indexPath.item]
            let isActive = (indexBinding.wrappedValue == indexPath.item)
            cell.setContent(contentBuilder(indexPath.item, item, isActive))
            return cell
        }
        
        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let sorted = indexPaths.map(\.item).sorted()
            let set = IndexSet(sorted)
            let sizePx = CGSize(width: collectionView.bounds.width * UIScreen.main.scale,
                                height: collectionView.bounds.height * UIScreen.main.scale)
            onPrefetch(set, sizePx)
        }
        
        func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            let sorted = indexPaths.map(\.item).sorted()
            let set = IndexSet(sorted)
            let sizePx = CGSize(width: collectionView.bounds.width * UIScreen.main.scale,
                                height: collectionView.bounds.height * UIScreen.main.scale)
            onCancelPrefetch(set, sizePx)
        }
        
        override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            Diagnostics.log("PagedCollection willDisplay idx=\(indexPath.item)")
            if indexPath.item == 0 {
                BootUIMetrics.shared.endFirstFrameToFirstCellMountedOnce()
                FirstLaunchProbe.shared.firstCellMounted()
            }
            if let cell = cell as? Cell, items.indices.contains(indexPath.item) {
                let item = items[indexPath.item]
                let isActive = (indexBinding.wrappedValue == indexPath.item)
                cell.setContent(contentBuilder(indexPath.item, item, isActive))
            }
        }
        
        override func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard collectionView.bounds.height > 0 else { return }
            guard !isBridgeLockActive else { return }  // We own the index until bridge scroll completes

            let target = computedPage()
            if target != indexBinding.wrappedValue {
                indexBinding.wrappedValue = target
                Diagnostics.log("PagedCollection current index=\(target) [scroll]")
                refreshVisibleCellsActiveState()
                updatePrefetchWindow(for: target)
            }

            let h = collectionView.bounds.height
            let current = indexBinding.wrappedValue
            let baseY = h * CGFloat(current)
            let y = scrollView.contentOffset.y
            let delta = y - baseY
            guard delta > 0 else {
                hideGateSpinner()
                return
            }
            var i = current + 1
            while items.indices.contains(i), isPageReady(i) {
                i += 1
            }
            guard items.indices.contains(i) else {
                hideGateSpinner()
                return
            }
            let readySpan = max(0, i - current - 1)
            let cap = CGFloat(readySpan) * h + h * gateFraction
            if delta > cap {
                scrollView.contentOffset.y = baseY + cap
                if scrollView.isDragging {
                    showGateSpinner()
                }
            } else if !scrollView.isDragging {
                hideGateSpinner()
            }
        }
        
        override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            Diagnostics.log("PagedCollection begin dragging")
            onScrollInteracting?(true)
        }
        
        override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            Diagnostics.log("PagedCollection end decelerating")
            commitPageChange()
            hideGateSpinner()
            onScrollInteracting?(false)
        }
        
        override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            Diagnostics.log("PagedCollection end dragging decelerate=\(decelerate)")
            if !decelerate {
                commitPageChange()
                hideGateSpinner()
                onScrollInteracting?(false)
            }
        }
        
        override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            Diagnostics.log("PagedCollection end scrolling animation")
            commitPageChange()
            hideGateSpinner()
            onScrollInteracting?(false)
        }
        
        private func commitPageChange() {
            guard !isBridgeLockActive else { return }  // Don't overwrite during bridge
            let target = computedPage()
            guard indexBinding.wrappedValue != target else {
                refreshVisibleCellsActiveState()
                updatePrefetchWindow(for: target)
                return
            }
            indexBinding.wrappedValue = target
            Diagnostics.log("PagedCollection current index=\(target)")
            refreshVisibleCellsActiveState()
            updatePrefetchWindow(for: target)
        }

        private func updatePrefetchWindow(for page: Int) {
            guard !items.isEmpty else {
                prefetchedIndices = []
                return
            }
            let desired = desiredWindow(for: page)
            let adds = desired.subtracting(prefetchedIndices)
            let removes = prefetchedIndices.subtracting(desired)

            let addOrder = adds.sorted()
            let removeOrder = removes.sorted()

            let sizePx = CGSize(width: collectionView.bounds.width * UIScreen.main.scale,
                                height: collectionView.bounds.height * UIScreen.main.scale)
            if !addOrder.isEmpty {
                Diagnostics.log("PagedCollection prefetch add indices=\(addOrder)")
                onPrefetch(IndexSet(addOrder), sizePx)
            }
            if !removeOrder.isEmpty {
                Diagnostics.log("PagedCollection prefetch cancel indices=\(removeOrder)")
                onCancelPrefetch(IndexSet(removeOrder), sizePx)
            }

            prefetchedIndices = desired
        }

        private func desiredWindow(for index: Int) -> Set<Int> {
            let candidates = [index - 1, index, index + 1, index + 2, index + 3, index + 4,  index + 5, index + 6,  index + 7, index + 8]
            let valid = candidates.filter { $0 >= 0 && $0 < items.count }
            return Set(valid)
        }
        
        private func refreshVisibleCellsActiveState() {
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: indexPath) as? Cell,
                      items.indices.contains(indexPath.item) else { continue }
                let item = items[indexPath.item]
                let isActive = (indexBinding.wrappedValue == indexPath.item)
                Diagnostics.log("PagedCollection refresh cell idx=\(indexPath.item) isActive=\(isActive)")
                cell.setContent(contentBuilder(indexPath.item, item, isActive))
            }
        }
        
        final class Cell: UICollectionViewCell {
            private var hostingController: UIHostingController<AnyView>?
            
            override init(frame: CGRect) {
                super.init(frame: frame)
                backgroundColor = .black
            }
            
            required init?(coder: NSCoder) {
                super.init(coder: coder)
                backgroundColor = .black
            }
            
            func setContent(_ view: AnyView) {
                if let hostingController {
                    hostingController.rootView = view
                } else {
                    let hc = UIHostingController(rootView: view)
                    hostingController = hc
                    hc.view.backgroundColor = .clear
                    hc.view.translatesAutoresizingMaskIntoConstraints = false
                    contentView.addSubview(hc.view)
                    NSLayoutConstraint.activate([
                        hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                        hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                        hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                        hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                    ])
                    Diagnostics.log("PagedCollection mount hostingController")
                }
            }
        }
        
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            collectionView.bounds.size
        }
    }
}
