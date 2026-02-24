//
//  FeedImpl2_TwoLayers.swift
//  Names 3
//
//  Implementation 2: Two distinct layers - preview (first frame) and playback.
//  Preview layer: shows first-frame image or low-res thumbnail; never has AVPlayer.
//  Playback layer: shared player, only attached when cell is active.
//  Never the same player on two layers - avoids audio-only black-screen issue.
//

import UIKit
import AVFoundation
import Photos

final class FeedImpl2CellView: UIView, FeedCellContentUpdatable, FeedCellTeardownable {

    private let asset: PHAsset
    private var isActive: Bool
    private weak var sharedPlayer: SingleAssetPlayer?

    private let previewLayerView = UIImageView()  // First frame only, no AVPlayer
    private let playbackLayerView = PlayerLayerView()  // Shared player only when active
    private var firstFrameLoadTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var layerReadyObserver: NSKeyValueObservation?

    init(asset: PHAsset, isActive: Bool, sharedPlayer: SingleAssetPlayer?) {
        self.asset = asset
        self.isActive = isActive
        self.sharedPlayer = sharedPlayer
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .black

        previewLayerView.contentMode = .scaleAspectFill
        previewLayerView.clipsToBounds = true
        previewLayerView.backgroundColor = .black
        addSubview(previewLayerView)
        previewLayerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewLayerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            previewLayerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            previewLayerView.topAnchor.constraint(equalTo: topAnchor),
            previewLayerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        playbackLayerView.backgroundColor = .black
        playbackLayerView.playerLayer.videoGravity = .resizeAspectFill
        playbackLayerView.playerLayer.player = nil  // Never assign until active
        addSubview(playbackLayerView)
        playbackLayerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playbackLayerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playbackLayerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playbackLayerView.topAnchor.constraint(equalTo: topAnchor),
            playbackLayerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        playbackLayerView.alpha = 0  // Hidden until ready

        loadFirstFrame()
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        isUserInteractionEnabled = true

        if isActive, let shared = sharedPlayer {
            configureActive(shared: shared)
        }
    }

    private func loadFirstFrame() {
        let size = CGSize(width: 800, height: 800)
        firstFrameLoadTask = Task { @MainActor in
            let image = await ImagePrefetcher.shared.requestVideoFirstFrame(for: asset, targetSize: size)
            guard !Task.isCancelled else { return }
            previewLayerView.image = image
        }
    }

    private func configureActive(shared: SingleAssetPlayer) {
        shared.setAsset(asset)
        shared.setActive(true)
        // Strict: ensure no other layer has this player before we assign
        playbackLayerView.playerLayer.player = nil
        playbackLayerView.playerLayer.player = shared.player
        playbackLayerView.setNeedsLayout()
        playbackLayerView.layoutIfNeeded()
        layerReadyObserver = playbackLayerView.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard let self, layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                self.showPlaybackHidePreview()
            }
        }
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            if playbackLayerView.superview != nil { showPlaybackHidePreview() }
        }
    }

    private func showPlaybackHidePreview() {
        timeoutTask?.cancel()
        timeoutTask = nil
        layerReadyObserver?.invalidate()
        layerReadyObserver = nil
        firstFrameLoadTask?.cancel()
        firstFrameLoadTask = nil
        UIView.animate(withDuration: 0.08) {
            self.previewLayerView.alpha = 0
            self.playbackLayerView.alpha = 1
        } completion: { _ in
            self.previewLayerView.removeFromSuperview()
        }
    }

    private func configureInactive() {
        layerReadyObserver?.invalidate()
        layerReadyObserver = nil
        sharedPlayer?.setActive(false)
        playbackLayerView.playerLayer.player = nil  // Unbind before any other layer gets it
        playbackLayerView.alpha = 0
        previewLayerView.alpha = 1
    }

    @objc private func handleTap() {
        guard isActive, let shared = sharedPlayer else { return }
        shared.togglePlay()
    }

    func updateIsActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        if let shared = sharedPlayer {
            if active {
                configureActive(shared: shared)
            } else {
                configureInactive()
            }
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
            sharedPlayer?.setActive(false)
        }
        playbackLayerView.playerLayer.player = nil
        previewLayerView.removeFromSuperview()
        playbackLayerView.removeFromSuperview()
    }
}
