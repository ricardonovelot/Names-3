import UIKit
import Photos
import SwiftUI
import Vision
import SwiftData

final class PhotoFullscreenCell: UICollectionViewCell {
    static let reuseIdentifier = "PhotoFullscreenCell"
    
    private let imageView = UIImageView()
    private var faceOverlayContainer = UIView()
    private var faceOverlayViews: [FaceOverlayView] = []
    private var currentRequestID: PHImageRequestID?
    private var representedAssetIdentifier: String?
    
    private var detectedFaces: [VNFaceObservation] = []
    private var fullImage: UIImage?
    private var currentAsset: PHAsset?
    
    var onFaceTapped: ((VNFaceObservation, UIImage, Int) -> Void)?
    var onPhotoTapped: (() -> Void)?
    var onPhotoLongPress: ((PHAsset) -> Void)?
    var onFacesDetected: ((UIImage, [VNFaceObservation], String) -> Void)?  // Now passes asset ID
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.backgroundColor = .black
        
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        contentView.addSubview(imageView)
        
        faceOverlayContainer.translatesAutoresizingMaskIntoConstraints = false
        faceOverlayContainer.isUserInteractionEnabled = true
        faceOverlayContainer.backgroundColor = .clear
        contentView.addSubview(faceOverlayContainer)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleImageTap))
        imageView.addGestureRecognizer(tapGesture)
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0.5
        imageView.addGestureRecognizer(longPressGesture)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            
            faceOverlayContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            faceOverlayContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            faceOverlayContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            faceOverlayContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    
    @objc private func handleImageTap(_ gesture: UITapGestureRecognizer) {
        onPhotoTapped?()
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        if let asset = currentAsset {
            onPhotoLongPress?(asset)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        if let requestID = currentRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            currentRequestID = nil
        }
        
        representedAssetIdentifier = nil
        imageView.image = nil
        fullImage = nil
        currentAsset = nil
        clearFaceOverlays()
    }
    
    func configure(
        with asset: PHAsset,
        imageManager: PHCachingImageManager,
        targetSize: CGSize
    ) {
        let assetIdentifier = asset.localIdentifier
        representedAssetIdentifier = assetIdentifier
        currentAsset = asset
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        currentRequestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, info in
            guard let self = self else { return }
            
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
            guard !isCancelled else { return }
            
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            
            guard self.representedAssetIdentifier == assetIdentifier else {
                return
            }
            
            if let image = image, !isDegraded {
                self.imageView.image = image
                self.fullImage = image
                
                // Wait for layout before detecting faces
                // Capture assetIdentifier here before async work
                DispatchQueue.main.async { [weak self, assetIdentifier] in
                    guard let self = self else { return }
                    // Only detect if this asset is still what we're showing
                    guard self.representedAssetIdentifier == assetIdentifier else { return }
                    self.detectAndShowFaces(in: image, assetID: assetIdentifier)
                }
            }
        }
    }
    
    private func detectAndShowFaces(in image: UIImage, assetID: String) {
        guard let cgImage = image.cgImage else { return }
        
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        
        do {
            try handler.perform([request])
            
            if let observations = request.results as? [VNFaceObservation] {
                // Capture assetID and representedAssetIdentifier before async dispatch
                let capturedAssetID = assetID
                let capturedRepresentedID = self.representedAssetIdentifier
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Only update if this cell is still showing the same asset
                    guard self.representedAssetIdentifier == capturedAssetID,
                          capturedRepresentedID == capturedAssetID else {
                        print("⚠️ [PhotoFullscreenCell] Ignoring stale face detection for \(capturedAssetID), cell now shows \(self.representedAssetIdentifier ?? "nil")")
                        return
                    }
                    
                    self.detectedFaces = observations
                    
                    // Notify coordinator with asset ID (not index!)
                    self.onFacesDetected?(image, observations, capturedAssetID)
                    
                    if !observations.isEmpty {
                        self.showFaceOverlays(observations: observations, imageSize: image.size)
                    }
                }
            }
        } catch {
            print("❌ [PhotoFullscreenCell] Face detection failed: \(error)")
        }
    }
    
    private func showFaceOverlays(observations: [VNFaceObservation], imageSize: CGSize) {
        clearFaceOverlays()
        
        guard let displayedImage = imageView.image else { return }
        
        for (index, observation) in observations.enumerated() {
            let overlayView = FaceOverlayView(index: index)
            overlayView.translatesAutoresizingMaskIntoConstraints = false
            overlayView.alpha = 0
            faceOverlayContainer.addSubview(overlayView)
            faceOverlayViews.append(overlayView)
            
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleFaceOverlayTap(_:)))
            overlayView.addGestureRecognizer(tapGesture)
            overlayView.tag = index
        }
        
        // Force layout and update positions
        layoutIfNeeded()
        updateFaceOverlayPositions()
        
        UIView.animate(withDuration: 0.3, delay: 0.15) {
            self.faceOverlayViews.forEach { $0.alpha = 1.0 }
        }
    }
    
    @objc private func handleFaceOverlayTap(_ gesture: UITapGestureRecognizer) {
        guard let overlayView = gesture.view as? FaceOverlayView else { return }
        let index = overlayView.tag
        
        guard index < detectedFaces.count, let image = fullImage else { return }
        
        let observation = detectedFaces[index]
        onFaceTapped?(observation, image, index)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateFaceOverlayPositions()
    }
    
    private func updateFaceOverlayPositions() {
        guard let displayedImage = imageView.image, !detectedFaces.isEmpty else { return }
        guard faceOverlayViews.count == detectedFaces.count else { return }
        
        let imageSize = displayedImage.size
        let imageViewBounds = imageView.bounds
        
        // Calculate the actual rect where the image is displayed (accounting for aspect fit)
        let displayedImageRect = calculateDisplayedImageRect(
            imageSize: imageSize,
            inViewBounds: imageViewBounds
        )
        
        for (index, overlayView) in faceOverlayViews.enumerated() {
            guard index < detectedFaces.count else { continue }
            
            let observation = detectedFaces[index]
            let bb = observation.boundingBox
            
            // Convert Vision coordinates (bottom-left origin, normalized 0-1) to UIKit (top-left origin, pixels)
            let x = displayedImageRect.origin.x + bb.origin.x * displayedImageRect.width
            let y = displayedImageRect.origin.y + (1 - bb.origin.y - bb.height) * displayedImageRect.height
            let width = bb.width * displayedImageRect.width
            let height = bb.height * displayedImageRect.height
            
            // Add padding to make it easier to tap
            let padding: CGFloat = 12
            overlayView.frame = CGRect(
                x: x - padding,
                y: y - padding,
                width: width + padding * 2,
                height: height + padding * 2
            )
        }
    }
    
    private func calculateDisplayedImageRect(imageSize: CGSize, inViewBounds viewBounds: CGRect) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewBounds.width / viewBounds.height
        
        var displayedImageRect: CGRect
        
        if imageAspect > viewAspect {
            // Image is wider - will be constrained by width
            let displayHeight = viewBounds.width / imageAspect
            let yOffset = (viewBounds.height - displayHeight) / 2
            displayedImageRect = CGRect(
                x: viewBounds.origin.x,
                y: viewBounds.origin.y + yOffset,
                width: viewBounds.width,
                height: displayHeight
            )
        } else {
            // Image is taller - will be constrained by height
            let displayWidth = viewBounds.height * imageAspect
            let xOffset = (viewBounds.width - displayWidth) / 2
            displayedImageRect = CGRect(
                x: viewBounds.origin.x + xOffset,
                y: viewBounds.origin.y,
                width: displayWidth,
                height: viewBounds.height
            )
        }
        
        return displayedImageRect
    }
    
    private func clearFaceOverlays() {
        faceOverlayViews.forEach { $0.removeFromSuperview() }
        faceOverlayViews.removeAll()
        detectedFaces.removeAll()
    }
}

final class FaceOverlayView: UIView {
    let index: Int
    private let circleLayer = CAShapeLayer()
    private let labelBackground = UIView()
    private let label = UILabel()
    
    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        isUserInteractionEnabled = true
        backgroundColor = .clear
        
        circleLayer.strokeColor = UIColor.systemYellow.cgColor
        circleLayer.fillColor = UIColor.systemYellow.withAlphaComponent(0.15).cgColor
        circleLayer.lineWidth = 3
        layer.addSublayer(circleLayer)
        
        labelBackground.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.95)
        labelBackground.layer.cornerRadius = 16
        labelBackground.clipsToBounds = true
        labelBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelBackground)
        
        label.text = "?"
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.textColor = .black
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        labelBackground.addSubview(label)
        
        NSLayoutConstraint.activate([
            labelBackground.centerXAnchor.constraint(equalTo: centerXAnchor),
            labelBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 8),
            labelBackground.widthAnchor.constraint(equalToConstant: 36),
            labelBackground.heightAnchor.constraint(equalToConstant: 36),
            
            label.centerXAnchor.constraint(equalTo: labelBackground.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: labelBackground.centerYAnchor)
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let path = UIBezierPath(ovalIn: bounds)
        circleLayer.path = path.cgPath
    }
}