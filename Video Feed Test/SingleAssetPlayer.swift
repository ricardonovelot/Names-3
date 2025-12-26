import Foundation
import SwiftUI
import AVFoundation
import Photos
import QuartzCore
import UIKit
import Combine
import MediaPlayer

@MainActor
final class SingleAssetPlayer: ObservableObject {
    let player = AVPlayer()
    
    private var pendingRequestID: PHImageRequestID = PHInvalidImageRequestID
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var likelyToKeepUpObserver: NSKeyValueObservation?
    private var appActiveObserver: NSObjectProtocol?
    private var appInactiveObserver: NSObjectProtocol?
    private var timeObserver: Any?
    @Published var hasPresentedFirstFrame: Bool = false

    private var loadTask: Task<Void, Never>?
    private var currentAssetID: String?
    private var isActive: Bool = false

    private var diagProbe: PlayerProbe?
    private var diagStart: CFTimeInterval = 0

    private var volumeUserCancellable: AnyCancellable?
    private var musicCancellable: AnyCancellable?
    private var overrideChangedObserver: NSObjectProtocol?
    private var appliedSongID: String?
    private var songOverrideTask: Task<Void, Never>?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true

        PlaybackRegistry.shared.register(player)
        VideoVolumeManager.shared.apply(to: player)

        volumeUserCancellable = VideoVolumeManager.shared.$userVolume
            .sink { [weak self] _ in
                self?.recomputeVolume()
            }
        musicCancellable = MusicPlaybackMonitor.shared.$isPlaying
            .sink { [weak self] _ in
                self?.recomputeVolume()
            }

        appActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleAppDidBecomeActive()
        }
        appInactiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handleAppWillResignActive()
        }
        overrideChangedObserver = NotificationCenter.default.addObserver(forName: .videoAudioOverrideChanged, object: nil, queue: .main) { [weak self] note in
            guard let self, let id = note.userInfo?["id"] as? String else { return }
            if id == self.currentAssetID {
                self.recomputeVolume()
                self.applySongIfAny()
            }
        }
    }

    deinit {
        if let appActiveObserver { NotificationCenter.default.removeObserver(appActiveObserver) }
        if let appInactiveObserver { NotificationCenter.default.removeObserver(appInactiveObserver) }
        if let overrideChangedObserver { NotificationCenter.default.removeObserver(overrideChangedObserver) }
        let p = player
        Task { @MainActor in
            PlaybackRegistry.shared.unregister(p)
        }
        volumeUserCancellable?.cancel()
        volumeUserCancellable = nil
        musicCancellable?.cancel()
        musicCancellable = nil
        songOverrideTask?.cancel()
        songOverrideTask = nil
    }
    
    func setAsset(_ asset: PHAsset) {
        guard currentAssetID != asset.localIdentifier else { return }
        cancel()
        currentAssetID = asset.localIdentifier
        hasPresentedFirstFrame = false
        appliedSongID = nil
        
        Diagnostics.log("TikTokCell configure: \(asset.diagSummary)")
        PlayerLeakDetector.shared.snapshotActive(log: true)
        diagProbe = PlayerProbe(player: player, context: "TikTokCell", assetID: asset.localIdentifier)
        diagStart = CACurrentMediaTime()

        recomputeVolume()

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadAsset(asset)
        }
    }

    func setActive(_ active: Bool) {
        if !active { persistPlaybackPosition() }
        isActive = active
        if active {
            PlaybackRegistry.shared.willPlay(player)
        }
        applySongIfAny()
        updatePlaybackForCurrentState()
    }

    func togglePlay() {
        if player.timeControlStatus == .playing {
            player.pause()
            AppleMusicController.shared.pauseIfManaged()
        } else {
            PlaybackRegistry.shared.willPlay(player)
            player.play()
            AppleMusicController.shared.resumeIfManaged()
        }
    }
    
    func cancel() {
        persistPlaybackPosition()

        loadTask?.cancel()
        loadTask = nil

        songOverrideTask?.cancel()
        songOverrideTask = nil

        if pendingRequestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(pendingRequestID)
            pendingRequestID = PHInvalidImageRequestID
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObserver = nil
        likelyToKeepUpObserver = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        hasPresentedFirstFrame = false
        player.replaceCurrentItem(with: nil)
        diagProbe = nil
        currentAssetID = nil
        Diagnostics.log("TikTokCell cancel")
    }

    private func persistPlaybackPosition() {
        guard let id = currentAssetID, let item = player.currentItem else { return }
        let time = player.currentTime()
        let duration = item.duration
        Task { await PlaybackPositionStore.shared.record(id: id, time: time, duration: duration) }
    }

    private func handleAppDidBecomeActive() {
        guard isActive else { return }
        updatePlaybackForCurrentState()
    }

    private func handleAppWillResignActive() {
        persistPlaybackPosition()
        player.pause()
        AppleMusicController.shared.pauseIfManaged()
    }

    private func attachObservers(to item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        statusObserver = nil
        likelyToKeepUpObserver = nil
        
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                if self.isActive {
                    PlaybackRegistry.shared.willPlay(self.player)
                    self.player.play()
                } else {
                    self.player.pause()
                }
            }
        }
        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            if item.status == .failed {
                self.player.replaceCurrentItem(with: nil)
            } else if item.status == .readyToPlay {
                if let id = self.currentAssetID {
                    DownloadTracker.shared.markPlaybackReady(id: id)
                    NotificationCenter.default.post(name: .videoPlaybackItemReady, object: nil, userInfo: ["id": id])
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let id = self.currentAssetID, let pos = await PlaybackPositionStore.shared.position(for: id, duration: item.duration) {
                        self.player.seek(to: pos, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            self.updatePlaybackForCurrentState()
                        }
                    } else {
                        self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            self.updatePlaybackForCurrentState()
                        }
                    }
                }
            }
        }
        likelyToKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .initial]) { [weak self] _, _ in
            self?.updatePlaybackForCurrentState()
        }
    }

    private func updatePlaybackForCurrentState() {
        guard let item = player.currentItem else { return }
        if item.status != .readyToPlay {
            return
        }
        if isActive {
            if item.isPlaybackLikelyToKeepUp {
                PlaybackRegistry.shared.willPlay(player)
                player.play()
            } else {
                player.pause()
            }
        } else {
            player.pause()
        }
    }

    private func applyItem(_ item: AVPlayerItem) {
        attachObservers(to: item)
        player.replaceCurrentItem(with: item)
        item.preferredForwardBufferDuration = 2.0
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        hasPresentedFirstFrame = false
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self else { return }
            if !self.hasPresentedFirstFrame, t.seconds > 0 {
                self.hasPresentedFirstFrame = true
                if let timeObserver = self.timeObserver {
                    self.player.removeTimeObserver(timeObserver)
                    self.timeObserver = nil
                }
            }
        }
    }

    private func loadAsset(_ asset: PHAsset) async {
        if let warm = await VideoPrefetcher.shared.asset(for: asset.localIdentifier, timeout: .milliseconds(450)) {
            diagProbe?.startPhase("TikTok_UsePrefetchedAsset")
            let item = AVPlayerItem(asset: warm)
            diagProbe?.attach(item: item)
            applyItem(item)
            diagProbe?.endPhase("TikTok_UsePrefetchedAsset")
            return
        }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .mediumQualityFormat
        options.isNetworkAccessAllowed = true
        options.progressHandler = { progress, _, _, _ in
            Task { @MainActor in
                DownloadTracker.shared.updateProgress(for: asset.localIdentifier, phase: .playerItem, progress: progress)
            }
        }

        diagProbe?.startPhase("TikTok_RequestPlayerItem")
        let (item, info) = await requestPlayerItemAsync(for: asset, options: options)
        let dt = CACurrentMediaTime() - self.diagStart
        Diagnostics.log("TikTokCell requestPlayerItem finished in \(String(format: "%.3f", dt))s")
        PhotoKitDiagnostics.logResultInfo(prefix: "TikTokCell request info", info: info)
        diagProbe?.endPhase("TikTok_RequestPlayerItem")

        guard !Task.isCancelled else { return }
        if let item {
            diagProbe?.attach(item: item)
            applyItem(item)
        } else {
            self.player.replaceCurrentItem(with: nil)
        }
    }

    private func requestPlayerItemAsync(for asset: PHAsset, options: PHVideoRequestOptions) async -> (AVPlayerItem?, [AnyHashable: Any]?) {
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (cont: CheckedContinuation<(AVPlayerItem?, [AnyHashable: Any]?), Never>) in
                let reqID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, info in
                    cont.resume(returning: (item, info))
                }
                self.pendingRequestID = reqID
            }
        }, onCancel: {
            Task { @MainActor in
                if self.pendingRequestID != PHInvalidImageRequestID {
                    PHImageManager.default().cancelImageRequest(self.pendingRequestID)
                    self.pendingRequestID = PHInvalidImageRequestID
                }
            }
        })
    }

    private func recomputeVolume() {
        let baseVolumeTask = Task { () -> Float in
            if let id = self.currentAssetID, let per = await VideoAudioOverrides.shared.volumeOverride(for: id) {
                return per
            }
            return VideoVolumeManager.shared.userVolume
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let base = await baseVolumeTask.value
            let effective: Float
            if MusicPlaybackMonitor.shared.isPlaying {
                effective = min(base, VideoVolumeManager.shared.duckingCapWhileMusic)
            } else {
                effective = base
            }
            self.player.volume = effective
        }
    }

    private func applySongIfAny() {
        songOverrideTask?.cancel()
        songOverrideTask = nil

        guard isActive else {
            if AppleMusicController.shared.hasActiveManagedPlayback {
                AppleMusicController.shared.pauseIfManaged()
            }
            return
        }

        guard let id = currentAssetID else {
            if AppleMusicController.shared.hasActiveManagedPlayback {
                AppleMusicController.shared.pauseIfManaged()
                AppleMusicController.shared.stopManaging()
            }
            appliedSongID = nil
            return
        }

        let requestID = id
        songOverrideTask = Task { [weak self] in
            guard let self else { return }
            let ref = await VideoAudioOverrides.shared.songReference(for: requestID)
            guard !Task.isCancelled else { return }
            await MainActor.run { [self] in
                guard self.isActive, self.currentAssetID == requestID else { return }
                self.updateAppleMusicPlayback(reference: ref)
            }
        }
    }

    @MainActor
    private func updateAppleMusicPlayback(reference: SongReference?) {
        if let reference {
            if let storeID = reference.appleMusicStoreID, appliedSongID == storeID {
                Diagnostics.log("UpdateAM same storeID=\(storeID) -> resumeIfManaged; nowPlaying=\(AppleMusicController.shared.managedNowPlayingStoreID() ?? "nil")")
                if AppleMusicController.shared.hasActiveManagedPlayback {
                    AppleMusicController.shared.resumeIfManaged()
                } else {
                    AppleMusicController.shared.play(reference: reference)
                }
            } else {
                Diagnostics.log("UpdateAM play reference=\(reference.debugKey)")
                AppleMusicController.shared.play(reference: reference)
                appliedSongID = reference.appleMusicStoreID
                Diagnostics.log("UpdateAM after play nowPlaying=\(AppleMusicController.shared.managedNowPlayingStoreID() ?? "nil")")
            }
        } else {
            if AppleMusicController.shared.hasActiveManagedPlayback {
                Diagnostics.log("UpdateAM no reference -> pause/stop")
                AppleMusicController.shared.pauseIfManaged()
                AppleMusicController.shared.stopManaging()
            }
            appliedSongID = nil
        }
    }
}