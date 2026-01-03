import UIKit

final class PhotosZoomingGridLayout: UICollectionViewFlowLayout {
    
    var zoomScale: CGFloat = 1.0 {
        didSet {
            guard oldValue != zoomScale else { return }
            invalidateLayout()
        }
    }
    
    private let baseColumns: CGFloat = 3.0
    
    override init() {
        super.init()
        scrollDirection = .vertical
        minimumInteritemSpacing = 1
        minimumLineSpacing = 1
        sectionInset = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func prepare() {
        super.prepare()
        
        guard let collectionView = collectionView else { return }
        
        let availableWidth = collectionView.bounds.width - sectionInset.left - sectionInset.right
        let columns = max(2, min(20, baseColumns / zoomScale))
        let actualColumns = round(columns)
        let totalSpacing = minimumInteritemSpacing * (actualColumns - 1)
        let itemWidth = max(40, (availableWidth - totalSpacing) / actualColumns)
        
        itemSize = CGSize(width: itemWidth, height: itemWidth)
    }
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
    
    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let attributes = super.layoutAttributesForElements(in: rect),
              let collectionView = collectionView else {
            return nil
        }
        
        let visibleRect = CGRect(
            origin: collectionView.contentOffset,
            size: collectionView.bounds.size
        )
        
        let centerX = visibleRect.midX
        let centerY = visibleRect.midY
        
        let maxDistance = sqrt(
            pow(collectionView.bounds.width, 2) +
            pow(collectionView.bounds.height, 2)
        ) / 2
        
        for attr in attributes where attr.representedElementCategory == .cell {
            let distanceX = abs(attr.center.x - centerX)
            let distanceY = abs(attr.center.y - centerY)
            let distance = sqrt(pow(distanceX, 2) + pow(distanceY, 2))
            
            let normalized = min(1, distance / maxDistance)
            
            let interpolationFactor = pow(1.0 - normalized, 2)
            let scale = 1.0 + (0.15 * interpolationFactor * min(1.0, zoomScale))
            
            let originalCenter = attr.center
            attr.transform = CGAffineTransform(scaleX: scale, y: scale)
            attr.center = originalCenter
            
            attr.zIndex = Int((1.0 - normalized) * 1000)
        }
        
        return attributes
    }
    
    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        guard let collectionView = collectionView else {
            return proposedContentOffset
        }
        
        let centerX = proposedContentOffset.x + collectionView.bounds.width / 2
        let centerY = proposedContentOffset.y + collectionView.bounds.height / 2
        let targetRect = CGRect(
            x: proposedContentOffset.x,
            y: proposedContentOffset.y,
            width: collectionView.bounds.width,
            height: collectionView.bounds.height
        )
        
        guard let attributes = layoutAttributesForElements(in: targetRect) else {
            return proposedContentOffset
        }
        
        var closestAttribute: UICollectionViewLayoutAttributes?
        var minDistance = CGFloat.greatestFiniteMagnitude
        
        for attr in attributes where attr.representedElementCategory == .cell {
            let distance = sqrt(
                pow(attr.center.x - centerX, 2) +
                pow(attr.center.y - centerY, 2)
            )
            
            if distance < minDistance {
                minDistance = distance
                closestAttribute = attr
            }
        }
        
        guard let closest = closestAttribute else {
            return proposedContentOffset
        }
        
        return CGPoint(
            x: closest.center.x - collectionView.bounds.width / 2,
            y: closest.center.y - collectionView.bounds.height / 2
        )
    }
}