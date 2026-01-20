import UIKit

/// Production-grade overlay system for grid zoom transitions
/// Implements Apple's cross-fade pattern used in Photos.app
final class PhotoGridZoomTransitionOverlay {
    
    // MARK: - Properties
    
    private weak var collectionView: UICollectionView?
    private var snapshotContainerView: UIView?
    private var isAnimating: Bool = false
    
    // Apple's timing constants from Photos app
    private let transitionDuration: TimeInterval = 0.3
    private let springDamping: CGFloat = 0.85
    private let springVelocity: CGFloat = 0.8
    
    // MARK: - Initialization
    
    init(collectionView: UICollectionView) {
        self.collectionView = collectionView
    }
    
    // MARK: - Public API
    
    /// Performs a cross-fade zoom transition with opacity animation
    /// - Parameters:
    ///   - transition: The layout transition to perform
    ///   - completion: Called when animation completes
    func performCrossFadeTransition(
        transition: @escaping () -> Void,
        completion: (() -> Void)? = nil
    ) {
        guard let collectionView = collectionView else {
            transition()
            completion?()
            return
        }
        
        // Prevent overlapping transitions
        if isAnimating {
            cleanupSnapshots()
        }
        
        isAnimating = true
        
        // Step 1: Capture current state
        let snapshots = captureVisibleCellSnapshots()
        
        guard !snapshots.isEmpty else {
            // No visible cells, just do instant transition
            transition()
            isAnimating = false
            completion?()
            return
        }
        
        // Step 2: Create and position snapshot overlay
        let overlayView = createSnapshotOverlay(with: snapshots)
        collectionView.superview?.insertSubview(overlayView, aboveSubview: collectionView)
        snapshotContainerView = overlayView
        
        // Step 3: Prepare new grid (set it to invisible)
        collectionView.alpha = 0.0
        
        // Step 4: Perform layout change (instant, behind overlay)
        transition()
        
        // Step 5: Force layout to establish new cell positions
        collectionView.layoutIfNeeded()
        
        // Step 6: Cross-fade animation
        UIView.animate(
            withDuration: transitionDuration,
            delay: 0,
            usingSpringWithDamping: springDamping,
            initialSpringVelocity: springVelocity,
            options: [.curveEaseInOut, .allowUserInteraction],
            animations: {
                // Fade out old grid overlay
                overlayView.alpha = 0.0
                
                // Fade in new grid
                collectionView.alpha = 1.0
            },
            completion: { [weak self] _ in
                // Step 7: Cleanup
                self?.cleanupSnapshots()
                self?.isAnimating = false
                completion?()
            }
        )
    }
    
    /// Immediately cancels any ongoing transition
    func cancelTransition() {
        cleanupSnapshots()
        collectionView?.alpha = 1.0
        isAnimating = false
    }
    
    // MARK: - Snapshot Capture
    
    private func captureVisibleCellSnapshots() -> [CellSnapshot] {
        guard let collectionView = collectionView else { return [] }
        
        var snapshots: [CellSnapshot] = []
        
        // Get all visible cells
        let visibleCells = collectionView.visibleCells
        
        for cell in visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell) else { continue }
            
            // Get the cell's current frame in collection view coordinates
            guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { continue }
            
            // Render the cell to an image
            guard let snapshot = renderCellSnapshot(cell) else { continue }
            
            let cellSnapshot = CellSnapshot(
                image: snapshot,
                frame: attributes.frame,
                indexPath: indexPath
            )
            
            snapshots.append(cellSnapshot)
        }
        
        print("📸 [Transition] Captured \(snapshots.count) cell snapshots")
        
        return snapshots
    }
    
    private func renderCellSnapshot(_ cell: UICollectionViewCell) -> UIImage? {
        // Use modern snapshot API for better quality
        let renderer = UIGraphicsImageRenderer(bounds: cell.bounds)
        
        let image = renderer.image { context in
            cell.layer.render(in: context.cgContext)
        }
        
        return image
    }
    
    // MARK: - Overlay Creation
    
    private func createSnapshotOverlay(with snapshots: [CellSnapshot]) -> UIView {
        guard let collectionView = collectionView else {
            return UIView()
        }
        
        // Container matches collection view frame
        let containerView = UIView(frame: collectionView.frame)
        containerView.clipsToBounds = true
        containerView.backgroundColor = .clear
        
        // Add each snapshot as an image view
        for snapshot in snapshots {
            let imageView = UIImageView(image: snapshot.image)
            imageView.frame = snapshot.frame
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            containerView.addSubview(imageView)
        }
        
        print("📸 [Transition] Created overlay with \(snapshots.count) images")
        
        return containerView
    }
    
    // MARK: - Cleanup
    
    private func cleanupSnapshots() {
        snapshotContainerView?.removeFromSuperview()
        snapshotContainerView = nil
    }
    
    // MARK: - Supporting Types
    
    private struct CellSnapshot {
        let image: UIImage
        let frame: CGRect
        let indexPath: IndexPath
    }
}