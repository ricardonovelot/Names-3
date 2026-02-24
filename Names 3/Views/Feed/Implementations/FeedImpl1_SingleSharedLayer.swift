//
//  FeedImpl1_SingleSharedLayer.swift
//  Names 3
//
//  Implementation 1: Single shared AVPlayerLayer reparented between cells.
//  One AVPlayer, one AVPlayerLayer. When active cell changes, the layer is moved
//  from the old cell to the new cell. Avoids AVFoundation's "only one layer
//  shows video" issue by never having multiple layers attached to the same player.
//

import UIKit
import AVFoundation
import Photos

// MARK: - Coordinator (owns the single layer + player)

@MainActor
final class SingleSharedLayerCoordinator {
    let player = SingleAssetPlayer()
    private let layerView = PlayerLayerView()
    private weak var currentHostView: UIView?
    private let parkingView = UIView()
    private var onReadyForDisplay: (() -> Void)?
    private var readyObserver: NSKeyValueObservation?

    init() {
        parkingView.isHidden = true
        parkingView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        layerView.playerLayer.videoGravity = .resizeAspectFill
        layerView.playerLayer.player = player.player
    }

    /// Call once when feed view is ready. Parking view must be in hierarchy for layer to render when parked.
    func installParkingView(in parentView: UIView) {
        guard parkingView.superview == nil else { return }
        parkingView.translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(parkingView)
        NSLayoutConstraint.activate([
            parkingView.widthAnchor.constraint(equalToConstant: 1),
            parkingView.heightAnchor.constraint(equalToConstant: 1),
            parkingView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            parkingView.topAnchor.constraint(equalTo: parentView.topAnchor)
        ])
    }

    /// Attach the shared layer to the given container. Detaches from previous host.
    func attachLayer(to containerView: UIView, onReady: (() -> Void)? = nil) {
        guard layerView.superview !== containerView else {
            onReady?()
            return
        }
        readyObserver?.invalidate()
        onReadyForDisplay = onReady
        if let cb = onReady {
            readyObserver = layerView.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                guard let self, layer.isReadyForDisplay else { return }
                DispatchQueue.main.async {
                    self.onReadyForDisplay?()
                    self.onReadyForDisplay = nil
                    self.readyObserver?.invalidate()
                    self.readyObserver = nil
                }
            }
        }
        if layerView.layer.superlayer == parkingView.layer {
            layerView.layer.removeFromSuperlayer()
        }
        layerView.removeFromSuperview()
        layerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(layerView)
        NSLayoutConstraint.activate([
            layerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            layerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            layerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            layerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        currentHostView = containerView
    }

    /// Detach the layer and park it. Parking view must be installed.
    func detachLayer() {
        guard layerView.superview != nil || layerView.layer.superlayer != nil else { return }
        readyObserver?.invalidate()
        readyObserver = nil
        onReadyForDisplay = nil
        layerView.removeFromSuperview()
        layerView.layer.removeFromSuperlayer()
        parkingView.layer.addSublayer(layerView.layer)
        layerView.layer.frame = parkingView.bounds
        currentHostView = nil
    }

    /// Move layer from parking into container. Call when cell becomes active.
    func moveLayerToContainer(_ containerView: UIView, onReady: (() -> Void)? = nil) {
        if layerView.layer.superlayer == parkingView.layer {
            layerView.layer.removeFromSuperlayer()
        }
        attachLayer(to: containerView, onReady: onReady)
    }

    func setAsset(_ asset: PHAsset) {
        player.setAsset(asset)
    }

    func setActive(_ active: Bool) {
        player.setActive(active)
    }

    func cancel() {
        player.cancel()
    }
}

// MARK: - Cell View

final class FeedImpl1CellView: UIView, FeedCellContentUpdatable, FeedCellTeardownable {

    private let asset: PHAsset
    private var isActive: Bool
    private weak var coordinator: SingleSharedLayerCoordinator?

    private let layerContainerView = UIView()
    private let firstFrameOverlay = UIImageView()
    private var firstFrameLoadTask: Task<Void, Never>?

    init(asset: PHAsset, isActive: Bool, coordinator: SingleSharedLayerCoordinator?) {
        self.asset = asset
        self.isActive = isActive
        self.coordinator = coordinator
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .black
        layerContainerView.backgroundColor = .black
        addSubview(layerContainerView)
        layerContainerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            layerContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            layerContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            layerContainerView.topAnchor.constraint(equalTo: topAnchor),
            layerContainerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        firstFrameOverlay.contentMode = .scaleAspectFill
        firstFrameOverlay.clipsToBounds = true
        firstFrameOverlay.backgroundColor = .black
        firstFrameOverlay.alpha = 0
        addSubview(firstFrameOverlay)
        firstFrameOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            firstFrameOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            firstFrameOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            firstFrameOverlay.topAnchor.constraint(equalTo: topAnchor),
            firstFrameOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        loadFirstFrame()
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        isUserInteractionEnabled = true

        if isActive, let coord = coordinator {
            coord.setAsset(asset)
            coord.setActive(true)
            coord.moveLayerToContainer(layerContainerView, onReady: { [weak self] in
                self?.hideFirstFrameOverlay()
            })
        }
    }

    private func loadFirstFrame() {
        let size = CGSize(width: 800, height: 800)
        firstFrameLoadTask = Task { @MainActor in
            let image = await ImagePrefetcher.shared.requestVideoFirstFrame(for: asset, targetSize: size)
            guard !Task.isCancelled else { return }
            firstFrameOverlay.image = image
            UIView.animate(withDuration: 0.12) { self.firstFrameOverlay.alpha = 1 }
        }
    }

    private func hideFirstFrameOverlay() {
        guard firstFrameOverlay.superview != nil else { return }
        firstFrameLoadTask?.cancel()
        firstFrameLoadTask = nil
        UIView.animate(withDuration: 0.06) { self.firstFrameOverlay.alpha = 0 } completion: { _ in
            self.firstFrameOverlay.removeFromSuperview()
        }
    }

    @objc private func handleTap() {
        guard isActive, let coord = coordinator else { return }
        coord.player.togglePlay()
    }

    func updateIsActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        guard let coord = coordinator else { return }

        if active {
            coord.moveLayerToContainer(layerContainerView)
            coord.setAsset(asset)
            coord.setActive(true)
            hideFirstFrameOverlay()
        } else {
            coord.setActive(false)
            coord.detachLayer()
        }
    }

    func tearDown() {
        firstFrameLoadTask?.cancel()
        firstFrameLoadTask = nil
        if isActive {
            coordinator?.setActive(false)
            coordinator?.detachLayer()
        }
        firstFrameOverlay.removeFromSuperview()
    }
}
