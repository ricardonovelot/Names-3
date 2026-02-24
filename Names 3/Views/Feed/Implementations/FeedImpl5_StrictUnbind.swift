//
//  FeedImpl5_StrictUnbind.swift
//  Names 3
//
//  Implementation 5: Current approach with strict nil-before-assign ordering.
//  Before assigning shared player to active cell's layer: ensure ALL other layers
//  that might have had it are explicitly set to nil first. Uses a coordinator
//  to sequence unbind→bind.
//

import UIKit
import AVFoundation
import Photos

// MARK: - Strict Unbind Coordinator

@MainActor
final class StrictUnbindCoordinator {
    let sharedPlayer = SingleAssetPlayer()
    private var activeLayer: AVPlayerLayer?

    /// Assign player to the given layer. Explicitly nils previous active layer first.
    func assignPlayer(to layer: AVPlayerLayer) {
        if activeLayer !== layer {
            activeLayer?.player = nil
            activeLayer = layer
        }
        layer.player = nil
        layer.player = sharedPlayer.player
    }

    func releaseLayer(_ layer: AVPlayerLayer) {
        if activeLayer === layer {
            activeLayer?.player = nil
            activeLayer = nil
        }
    }
}

// MARK: - Cell View

final class FeedImpl5CellView: UIView, FeedCellContentUpdatable, FeedCellTeardownable {

    private let asset: PHAsset
    private var isActive: Bool
    private weak var coordinator: StrictUnbindCoordinator?

    private let playerLayerView = PlayerLayerView()
    private let firstFrameOverlay = UIImageView()
    private var firstFrameLoadTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var layerReadyObserver: NSKeyValueObservation?

    init(asset: PHAsset, isActive: Bool, coordinator: StrictUnbindCoordinator?) {
        self.asset = asset
        self.isActive = isActive
        self.coordinator = coordinator
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .black
        playerLayerView.backgroundColor = .black
        playerLayerView.playerLayer.videoGravity = .resizeAspectFill
        playerLayerView.playerLayer.player = nil
        addSubview(playerLayerView)
        playerLayerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerLayerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerLayerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerLayerView.topAnchor.constraint(equalTo: topAnchor),
            playerLayerView.bottomAnchor.constraint(equalTo: bottomAnchor)
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
            coord.sharedPlayer.setAsset(asset)
            coord.sharedPlayer.setActive(true)
            coord.assignPlayer(to: playerLayerView.playerLayer)
            observeLayerReady()
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

    private func observeLayerReady() {
        layerReadyObserver = playerLayerView.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard let self, layer.isReadyForDisplay else { return }
            DispatchQueue.main.async { self.hideFirstFrameOverlay() }
        }
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            if firstFrameOverlay.superview != nil { hideFirstFrameOverlay() }
        }
    }

    private func hideFirstFrameOverlay() {
        guard firstFrameOverlay.superview != nil else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        firstFrameLoadTask?.cancel()
        firstFrameLoadTask = nil
        layerReadyObserver?.invalidate()
        layerReadyObserver = nil
        UIView.animate(withDuration: 0.06) { self.firstFrameOverlay.alpha = 0 } completion: { _ in
            self.firstFrameOverlay.removeFromSuperview()
        }
    }

    @objc private func handleTap() {
        guard isActive, let coord = coordinator else { return }
        coord.sharedPlayer.togglePlay()
    }

    func updateIsActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        guard let coord = coordinator else { return }
        if active {
            coord.sharedPlayer.setAsset(asset)
            coord.sharedPlayer.setActive(true)
            coord.assignPlayer(to: playerLayerView.playerLayer)
            observeLayerReady()
        } else {
            coord.sharedPlayer.setActive(false)
            coord.releaseLayer(playerLayerView.playerLayer)
            playerLayerView.playerLayer.player = nil
        }
    }

    func tearDown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        firstFrameLoadTask?.cancel()
        firstFrameLoadTask = nil
        layerReadyObserver?.invalidate()
        layerReadyObserver = nil
        if isActive {
            coordinator?.sharedPlayer.setActive(false)
            coordinator?.releaseLayer(playerLayerView.playerLayer)
        }
        playerLayerView.playerLayer.player = nil
        firstFrameOverlay.removeFromSuperview()
    }
}
