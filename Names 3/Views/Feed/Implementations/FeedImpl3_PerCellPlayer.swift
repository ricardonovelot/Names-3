//
//  FeedImpl3_PerCellPlayer.swift
//  Names 3
//
//  Implementation 3: One AVPlayer per visible cell. No shared player.
//  Each cell owns its SingleAssetPlayer. Simpler mental model, no layer-sharing issues.
//  Trade-off: more memory (one player per cached cell).
//

import UIKit
import AVFoundation
import Photos

final class FeedImpl3CellView: UIView, FeedCellContentUpdatable, FeedCellTeardownable {

    private let asset: PHAsset
    private var isActive: Bool

    private let ownPlayer = SingleAssetPlayer()
    private let playerLayerView = PlayerLayerView()
    private let firstFrameOverlay = UIImageView()
    private var firstFrameLoadTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var layerReadyObserver: NSKeyValueObservation?

    init(asset: PHAsset, isActive: Bool, sharedPlayer: SingleAssetPlayer?) {
        self.asset = asset
        self.isActive = isActive
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .black

        playerLayerView.backgroundColor = .black
        playerLayerView.playerLayer.videoGravity = .resizeAspectFill
        playerLayerView.playerLayer.player = ownPlayer.player
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

        ownPlayer.setAsset(asset)
        ownPlayer.setActive(isActive)
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
        guard isActive else { return }
        ownPlayer.togglePlay()
    }

    func updateIsActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        ownPlayer.setActive(active)
    }

    func tearDown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        firstFrameLoadTask?.cancel()
        firstFrameLoadTask = nil
        layerReadyObserver?.invalidate()
        layerReadyObserver = nil
        ownPlayer.cancel()
        firstFrameOverlay.removeFromSuperview()
    }
}
