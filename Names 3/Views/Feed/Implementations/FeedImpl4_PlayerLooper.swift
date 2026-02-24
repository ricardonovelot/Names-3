//
//  FeedImpl4_PlayerLooper.swift
//  Names 3
//
//  Implementation 4: Shared player with AVPlayerLooper for seamless looping.
//  Uses AVQueuePlayer + AVPlayerLooper to avoid seek-to-zero on loop.
//

import UIKit
import AVFoundation
import Photos

// MARK: - Looper Coordinator

@MainActor
final class PlayerLooperCoordinator {
    private let queuePlayer = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var currentAssetID: String?
    private var loadTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var statusObserver: NSKeyValueObservation?
    private var likelyToKeepUpObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    var player: AVPlayer { queuePlayer }

    init() {
        queuePlayer.automaticallyWaitsToMinimizeStalling = true
        PlaybackRegistry.shared.register(queuePlayer)
        VideoVolumeManager.shared.apply(to: queuePlayer)
    }

    func setAsset(_ asset: PHAsset) {
        guard currentAssetID != asset.localIdentifier else { return }
        loadTask?.cancel()
        currentAssetID = asset.localIdentifier
        looper?.disableLooping()
        looper = nil
        queuePlayer.replaceCurrentItem(with: nil)

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let item = await PlayerItemPrefetcher.shared.item(for: asset.localIdentifier, timeout: .milliseconds(800)) {
                self.applyItem(item, asset: asset)
                return
            }
            if let avAsset = await VideoPrefetcher.shared.asset(for: asset.localIdentifier, timeout: .milliseconds(450)) {
                let item = AVPlayerItem(asset: avAsset)
                self.applyItem(item, asset: asset)
                return
            }
            let (item, _) = await PlayerItemBootstrapper.shared.awaitResult(asset: asset)
            guard !Task.isCancelled else { return }
            if let item {
                self.applyItem(item, asset: asset)
            }
        }
    }

    private func applyItem(_ item: AVPlayerItem, asset: PHAsset) {
        guard currentAssetID == asset.localIdentifier else { return }
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.replaceCurrentItem(with: item)
        attachObservers(to: item)
        if isActive {
            queuePlayer.play()
        }
    }

    private var isActive = false

    func setActive(_ active: Bool) {
        isActive = active
        if active {
            PlaybackRegistry.shared.willPlay(queuePlayer)
            queuePlayer.play()
        } else {
            queuePlayer.pause()
        }
    }

    func togglePlay() {
        if queuePlayer.timeControlStatus == .playing {
            queuePlayer.pause()
        } else {
            PlaybackRegistry.shared.willPlay(queuePlayer)
            queuePlayer.play()
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        endObserver.map { NotificationCenter.default.removeObserver($0) }
        statusObserver = nil
        likelyToKeepUpObserver = nil
        looper?.disableLooping()
        looper = nil
        currentAssetID = nil
        queuePlayer.replaceCurrentItem(with: nil)
    }

    private func attachObservers(to item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            // Looper handles this; no seek needed
        }
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self, item.status == .readyToPlay, self.isActive else { return }
            self.queuePlayer.play()
        }
        likelyToKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self, item.isPlaybackLikelyToKeepUp, self.isActive else { return }
            self.queuePlayer.play()
        }
    }
}

// MARK: - Cell View

final class FeedImpl4CellView: UIView, FeedCellContentUpdatable, FeedCellTeardownable {

    private let asset: PHAsset
    private var isActive: Bool
    private weak var coordinator: PlayerLooperCoordinator?

    private let playerLayerView = PlayerLayerView()
    private let firstFrameOverlay = UIImageView()
    private var firstFrameLoadTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var layerReadyObserver: NSKeyValueObservation?

    init(asset: PHAsset, isActive: Bool, coordinator: PlayerLooperCoordinator?) {
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
        playerLayerView.playerLayer.player = coordinator?.player
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
            coord.setAsset(asset)
            coord.setActive(true)
            bindAndObserveReady()
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

    private func bindAndObserveReady() {
        guard let coord = coordinator else { return }
        playerLayerView.playerLayer.player = nil
        playerLayerView.playerLayer.player = coord.player
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
        coord.togglePlay()
    }

    func updateIsActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        guard let coord = coordinator else { return }
        if active {
            coord.setAsset(asset)
            coord.setActive(true)
            bindAndObserveReady()
        } else {
            coord.setActive(false)
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
            coordinator?.setActive(false)
        }
        playerLayerView.playerLayer.player = nil
        firstFrameOverlay.removeFromSuperview()
    }
}
