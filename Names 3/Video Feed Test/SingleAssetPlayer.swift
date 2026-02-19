import Foundation
import SwiftUI
import AVFoundation
import Photos
import QuartzCore
import UIKit
import Combine
import MediaPlayer
import os
import os.signpost
import CoreMedia

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

    private var loadProbe: VideoLoadProbe?

    private var volumeUserCancellable: AnyCancellable?
    private var musicCancellable: AnyCancellable?
    private var overrideChangedObserver: NSObjectProtocol?
    private var appliedSongID: String?
    private var songOverrideTask: Task<Void, Never>?
    private var accessLogObserver: NSObjectProtocol?
    private var errorLogObserver: NSObjectProtocol?
    private var statusWatchdog: Task<Void, Never>?
    private var didLogUnknownOnce = false

    private var spAppleMusic: OSSignpostID?
    private var lastAMAttemptAt: CFTimeInterval = 0
    private var lastAMAttemptStoreID: String?
    private var amVerifyTask: Task<Void, Never>?

    private var playbackStalledObserver: NSObjectProtocol?
    private var timeJumpedObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var stallWatchdog: Task<Void, Never>?
    private var spApplyToReady: OSSignpostID?
    private var spApplyToFirstFrame: OSSignpostID?
    private var lastObservedTime: CMTime = .zero
    private var lastAdvanceWall: CFTimeInterval = 0
    private var isStalledFlag = false

    private var spPlaybackStall: OSSignpostID?
    private var lastActivatedWall: CFTimeInterval = 0

    #if DEBUG
    private var videoOutput: AVPlayerItemVideoOutput?
    private var renderWatchdog: Task<Void, Never>?
    private var lastRenderedWall: CFTimeInterval = 0
    #endif

    // Feature-flagged HDR policy
    private var sdrConversionEnabled: Bool { FeatureFlags.forceSDRForHDRPlayback }
    private var disableHDRMetadataEnabled: Bool { FeatureFlags.disableHDRMetadataOnPlayback }

    private struct HDRInfo {
        let colorPrimaries: String?
        let transferFunction: String?
        let ycbcrMatrix: String?
        let hasMasteringDisplay: Bool
        let hasContentLightLevel: Bool
        let isHLG: Bool
        let isPQ: Bool
        var isHDR: Bool { isHLG || isPQ || hasMasteringDisplay || hasContentLightLevel }
    }

    private func naturalPixelSize(for asset: AVAsset) -> CGSize {
        guard let track = asset.tracks(withMediaType: .video).first else { return .zero }
        let t = track.preferredTransform
        let size = track.naturalSize.applying(t)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }

    private func fourCCString(from desc: CMFormatDescription) -> String {
        let code = CMFormatDescriptionGetMediaSubType(desc)
        let c1 = Character(UnicodeScalar((code >> 24) & 0xff) ?? " ")
        let c2 = Character(UnicodeScalar((code >> 16) & 0xff) ?? " ")
        let c3 = Character(UnicodeScalar((code >> 8) & 0xff) ?? " ")
        let c4 = Character(UnicodeScalar(code & 0xff) ?? " ")
        return "\(c1)\(c2)\(c3)\(c4)"
    }

    private func videoSummary(for asset: AVAsset) -> String {
        let size = naturalPixelSize(for: asset)
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())
        let dur = max(0, CMTimeGetSeconds(asset.duration))
        let fpsF = asset.tracks(withMediaType: .video).first?.nominalFrameRate ?? 0
        let fps = Double(fpsF)
        let estBrF = asset.tracks(withMediaType: .video).first?.estimatedDataRate ?? 0
        let estKbps = estBrF > 0 ? Double(estBrF) / 1000.0 : 0
        let hdr = extractHDRInfo(from: asset).isHDR
        var codec = "unknown"
        if let fdAny = asset.tracks(withMediaType: .video).first?.formatDescriptions.first {
            let fd = fdAny as! CMFormatDescription
            codec = fourCCString(from: fd)
        }
        let actualSize = actualFileSizeBytes(ifLocalURLOf: asset)
        let estSize = estimatedAssetSizeBytes(for: asset)

        let sizePart: String = {
            if let actual = actualSize {
                return "size=\(bytesToMBString(actual))"
            } else if let est = estSize {
                return "size≈\(bytesToMBString(est))"
            } else {
                return "size≈n/a"
            }
        }()

        return String(format: "res=%dx%d dur=%.2fs fps=%.1f br≈%.0f kbps %@ codec=%@ hdr=%@",
                      w, h, dur, fps, estKbps, sizePart, codec, hdr ? "true" : "false")
    }

    private func estimatedAssetSizeBytes(for asset: AVAsset) -> Int64? {
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let br = max(0.0, Double(track.estimatedDataRate))
        let dur = max(0, CMTimeGetSeconds(asset.duration))
        guard br > 0, dur > 0 else { return nil }
        let bytes = (br / 8.0) * dur
        return Int64(bytes.rounded())
    }

    private func actualFileSizeBytes(ifLocalURLOf asset: AVAsset) -> Int64? {
        guard let urlAsset = asset as? AVURLAsset, urlAsset.url.isFileURL else { return nil }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: urlAsset.url.path)
            if let n = attrs[.size] as? NSNumber {
                return n.int64Value
            }
        } catch { }
        return nil
    }

    private func bytesToMBString(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.1f MB", mb)
    }

    private func computeAndLogVideoSummary(for item: AVPlayerItem) {
        let id = currentAssetID ?? "nil"
        let asset = item.asset
        Task.detached { [weak self] in
            guard let self else { return }
            _ = await asset.asyncLoadValues(forKeys: ["tracks", "duration", "playable"])
            guard let track = asset.tracks(withMediaType: .video).first else {
                Diagnostics.videoPerf("[VideoSummary] id=\(id) noVideoTrack")
                return
            }
            _ = await track.asyncLoadValues(forKeys: ["formatDescriptions", "naturalSize", "nominalFrameRate", "estimatedDataRate", "preferredTransform"])
            Diagnostics.videoPerf("[VideoSummary] id=\(id) \(await self.videoSummary(for: asset))")
        }
    }

    private func extractHDRInfo(from asset: AVAsset) -> HDRInfo {
        guard let track = asset.tracks(withMediaType: .video).first,
              let anyDesc = track.formatDescriptions.first
        else {
            return HDRInfo(colorPrimaries: nil, transferFunction: nil, ycbcrMatrix: nil, hasMasteringDisplay: false, hasContentLightLevel: false, isHLG: false, isPQ: false)
        }

        let desc = anyDesc as! CMFormatDescription

        guard let ext = CMFormatDescriptionGetExtensions(desc) as? [CFString: Any] else {
            return HDRInfo(colorPrimaries: nil, transferFunction: nil, ycbcrMatrix: nil, hasMasteringDisplay: false, hasContentLightLevel: false, isHLG: false, isPQ: false)
        }

        let primStr = ext[kCMFormatDescriptionExtension_ColorPrimaries] as? String
        let xferStr = ext[kCMFormatDescriptionExtension_TransferFunction] as? String
        let yccStr  = ext[kCMFormatDescriptionExtension_YCbCrMatrix] as? String

        let hasMD  = ext[kCMFormatDescriptionExtension_MasteringDisplayColorVolume] != nil
        let hasCLL = ext[kCMFormatDescriptionExtension_ContentLightLevelInfo] != nil

        let isHLG = (xferStr == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String))
        let isPQ  = (xferStr == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String))

        return HDRInfo(
            colorPrimaries: primStr,
            transferFunction: xferStr,
            ycbcrMatrix: yccStr,
            hasMasteringDisplay: hasMD,
            hasContentLightLevel: hasCLL,
            isHLG: isHLG,
            isPQ: isPQ
        )
    }

    private func makeRec709VideoComposition(for asset: AVAsset) -> AVVideoComposition? {
        let tracks = asset.tracks(withMediaType: .video)
        guard !tracks.isEmpty else {
            Diagnostics.log("[TikTokCell] makeRec709VideoComposition: No video tracks found in asset. Cannot create composition.")
            return nil
        }
        
        let comp = AVMutableVideoComposition(propertiesOf: asset)
        
        // Applying standard Rec.709 color space properties.
        // If an invalid CGColorRef is being signaled, it might be due to an underlying
        // issue with the asset's original color space or malformed metadata
        // that AVFoundation struggles to convert.
        comp.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        comp.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        comp.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        
        Diagnostics.log("[TikTokCell] makeRec709VideoComposition: Successfully created composition for asset with colorPrimaries=\(comp.colorPrimaries ?? "nil"), colorTransferFunction=\(comp.colorTransferFunction ?? "nil"), colorYCbCrMatrix=\(comp.colorYCbCrMatrix ?? "nil").")
        
        return comp
    }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true

        Diagnostics.log("HDR playback flags: disableHDRMetadata=\(disableHDRMetadataEnabled) forceSDRforHDR=\(sdrConversionEnabled)")

        PlaybackRegistry.shared.register(player)
        VideoVolumeManager.shared.apply(to: player)

        volumeUserCancellable = VideoVolumeManager.shared.$userVolume
            .sink { [weak self] _ in
                self?.recomputeVolume()
            }
        if FeatureFlags.enableAppleMusicIntegration {
            musicCancellable = MusicCenter.shared.$isPlaying
                .sink { [weak self] _ in
                    self?.recomputeVolume()
                }
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
        amVerifyTask?.cancel()
        amVerifyTask = nil
    }
    
    func setAsset(_ asset: PHAsset) {
        guard currentAssetID != asset.localIdentifier else { return }
        cancel()
        currentAssetID = asset.localIdentifier
        hasPresentedFirstFrame = false
        appliedSongID = nil
        lastAMAttemptAt = 0
        lastAMAttemptStoreID = nil
        amVerifyTask?.cancel()
        amVerifyTask = nil


        Diagnostics.log("TikTokCell configure: \(asset.diagSummary)")
        PlayerLeakDetector.shared.snapshotActive(log: true)
        diagProbe = PlayerProbe(player: player, context: "TikTokCell", assetID: asset.localIdentifier)
        loadProbe = VideoLoadProbe(assetID: asset.localIdentifier)
        Diagnostics.videoPerf("[VideoPerf] Tracking start id=\(asset.localIdentifier)")
        diagStart = CACurrentMediaTime()
        FirstLaunchProbe.shared.playerSetAsset(id: asset.localIdentifier)

        Task {
            await PlayerItemBootstrapper.shared.ensureStarted(asset: asset)
        }

        recomputeVolume()
        Diagnostics.log("[TikTokCell] replaceCurrentItem begin id=\(asset.localIdentifier)")

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadAsset(asset)
        }
    }

    func setActive(_ active: Bool) {
        if !active { persistPlaybackPosition() }
        isActive = active
        Diagnostics.log("[TikTokCell] setActive=\(active) appState=\(UIApplication.shared.applicationState.rawValue)")
        if active {
            lastActivatedWall = CACurrentMediaTime()
            PlaybackRegistry.shared.willPlay(player)
        }
        applySongIfAny()
        updatePlaybackForCurrentState()
    }

    func togglePlay() {
        if player.timeControlStatus == .playing {
            player.pause()
            if FeatureFlags.enableAppleMusicIntegration {
                AppleMusicController.shared.pauseIfManaged()
            }
        } else {
            PlaybackRegistry.shared.willPlay(player)
            player.play()
            if FeatureFlags.enableAppleMusicIntegration {
                AppleMusicController.shared.resumeIfManaged()
            }
        }
    }
    
    func cancel() {
        persistPlaybackPosition()

        loadTask?.cancel()
        loadTask = nil

        songOverrideTask?.cancel()
        songOverrideTask = nil
        amVerifyTask?.cancel()
        amVerifyTask = nil

        if pendingRequestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(pendingRequestID)
            pendingRequestID = PHInvalidImageRequestID
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let accessLogObserver {
            NotificationCenter.default.removeObserver(accessLogObserver)
            self.accessLogObserver = nil
        }
        if let errorLogObserver {
            NotificationCenter.default.removeObserver(errorLogObserver)
            self.errorLogObserver = nil
        }
        if let playbackStalledObserver {
            NotificationCenter.default.removeObserver(playbackStalledObserver)
            self.playbackStalledObserver = nil
        }
        if let timeJumpedObserver {
            NotificationCenter.default.removeObserver(timeJumpedObserver)
            self.timeJumpedObserver = nil
        }
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
        stallWatchdog?.cancel()
        stallWatchdog = nil
        spApplyToReady = nil
        isStalledFlag = false
        lastObservedTime = .zero
        lastAdvanceWall = 0
        statusObserver = nil
        likelyToKeepUpObserver = nil
        statusWatchdog?.cancel()
        statusWatchdog = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        stallWatchdog?.cancel()
        stallWatchdog = nil
        spApplyToReady = nil
        isStalledFlag = false
        lastObservedTime = .zero
        lastAdvanceWall = 0
        lastAMAttemptAt = 0
        lastAMAttemptStoreID = nil
        #if DEBUG
        if let out = videoOutput, let item = player.currentItem {
            item.remove(out)
        }
        videoOutput = nil
        renderWatchdog?.cancel()
        renderWatchdog = nil
        lastRenderedWall = 0
        #endif

        if let id = currentAssetID {
            Task { await PlayerItemBootstrapper.shared.cancel(id: id) }
        }

        loadProbe?.finish(cancelled: true)
        loadProbe = nil
        if let id = currentAssetID {
            Task { await NextVideoTraceCenter.shared.finish(cancelled: true, failed: false) }
        }

        hasPresentedFirstFrame = false
        player.replaceCurrentItem(with: nil)
        diagProbe = nil
        currentAssetID = nil
        Diagnostics.log("TikTokCell cancel")
        Diagnostics.signpostEnd("PlaybackStall", id: spPlaybackStall)
        spPlaybackStall = nil
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
        if FeatureFlags.enableAppleMusicIntegration {
            AppleMusicController.shared.pauseIfManaged()
        }
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
            Diagnostics.log("[TikTokCell] didPlayToEnd asset=\(self.currentAssetID ?? "nil") -> loop")
            self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                if self.isActive {
                    PlaybackRegistry.shared.willPlay(self.player)
                    self.player.play()
                } else {
                    self.player.pause()
                }
            }
        }
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
        failedToEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
            guard let self else { return }
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
            Diagnostics.log("[TikTokCell] FailedToPlayToEnd id=\(self.currentAssetID ?? "nil") error=\(String(describing: err?.localizedDescription)) domain=\(err?.domain ?? "nil") code=\(err?.code ?? 0)")
        }

        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self else { return }
            Diagnostics.log("[TikTokCell] item.status=\(item.status.rawValue) error=\(String(describing: item.error)) dur=\(CMTimeGetSeconds(item.asset.duration))s tag=\(Diagnostics.shortTag(for: self.currentAssetID ?? ""))")
            if item.status == .failed {
                self.loadProbe?.finish(failed: true)
                if let id = self.currentAssetID {
                    Task { await NextVideoTraceCenter.shared.finish(cancelled: false, failed: true) }
                }
                self.player.replaceCurrentItem(with: nil)
            } else if item.status == .readyToPlay {
                Diagnostics.signpostEnd("ApplyItemToReady", id: self.spApplyToReady)
                self.spApplyToReady = nil
                self.loadProbe?.markReady()
                Task { await NextVideoTraceCenter.shared.markReady() }
                let tracks = item.asset.tracks(withMediaType: .video)
                let size = tracks.first?.naturalSize.applying(tracks.first?.preferredTransform ?? .identity) ?? .zero
                Diagnostics.log("[TikTokCell] readyToPlay size=\(NSCoder.string(for: size)) fps=\(tracks.first?.nominalFrameRate ?? 0) tag=\(Diagnostics.shortTag(for: self.currentAssetID ?? "")))")

                let ranges = item.loadedTimeRanges.compactMap { $0.timeRangeValue }
                let totalBuffered = ranges.reduce(0.0) { $0 + CMTimeGetSeconds($1.duration) }
                let rangesStr = ranges
                    .map { r in "[\(String(format: "%.2f", CMTimeGetSeconds(r.start)))..+\(String(format: "%.2f", CMTimeGetSeconds(r.duration)))]" }
                    .joined(separator: ", ")
                Diagnostics.videoPerf(String(format: "[VideoReady] id=%@ buffered=%.2fs ranges={%@}",
                                             self.currentAssetID ?? "nil",
                                             totalBuffered,
                                             rangesStr))

                if let id = self.currentAssetID {
                    DownloadTracker.shared.markPlaybackReady(id: id)
                    NotificationCenter.default.post(name: .videoPlaybackItemReady, object: nil, userInfo: ["id": id])
                    FirstLaunchProbe.shared.playerItemReady(id: id)
                }
                self.statusWatchdog?.cancel()
                self.statusWatchdog = nil
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
            } else if item.status == .unknown {
                if !self.didLogUnknownOnce, let id = self.currentAssetID {
                    self.didLogUnknownOnce = true
                    FirstLaunchProbe.shared.playerItemStatusUnknownFirst(id: id)
                }
            }
        }
        likelyToKeepUpObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .initial]) { [weak self] item, _ in
            Diagnostics.log("[TikTokCell] isPlaybackLikelyToKeepUp=\(item.isPlaybackLikelyToKeepUp)")
            FirstLaunchProbe.shared.playerLikelyToKeepUp(item.isPlaybackLikelyToKeepUp)
            self?.updatePlaybackForCurrentState()
        }

        if let playbackStalledObserver {
            NotificationCenter.default.removeObserver(playbackStalledObserver)
            self.playbackStalledObserver = nil
        }
        playbackStalledObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            let reason = self.player.reasonForWaitingToPlay?.rawValue ?? "nil"
            let likely = item.isPlaybackLikelyToKeepUp
            let empty = item.isPlaybackBufferEmpty
            let full = item.isPlaybackBufferFull
            let t = CMTimeGetSeconds(self.player.currentTime())
            let ranges = item.loadedTimeRanges.compactMap { $0.timeRangeValue }
                .map { r in "[\(String(format: "%.2f", CMTimeGetSeconds(r.start)))..+\(String(format: "%.2f", CMTimeGetSeconds(r.duration)))]" }
                .joined(separator: ", ")
            Diagnostics.log("[TikTokCell] PLAYBACK STALLED id=\(self.currentAssetID ?? "nil") t=\(String(format: "%.2f", t))s reason=\(reason) likely=\(likely) empty=\(empty) full=\(full) loaded=\(ranges)")
            self.isStalledFlag = true
            Diagnostics.signpostBegin("PlaybackStall", id: &self.spPlaybackStall)
            self.loadProbe?.stallBegan()
            Task { await NextVideoTraceCenter.shared.stallBegan() }
        }

        if let timeJumpedObserver {
            NotificationCenter.default.removeObserver(timeJumpedObserver)
            self.timeJumpedObserver = nil
        }
        timeJumpedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemTimeJumped, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            let t = CMTimeGetSeconds(self.player.currentTime())
            Diagnostics.log("[TikTokCell] timeJumped id=\(self.currentAssetID ?? "nil") t=\(String(format: "%.2f", t))s")
        }
    }

    private func updatePlaybackForCurrentState() {
        guard let item = player.currentItem else { return }
        if item.status != .readyToPlay {
            if let id = currentAssetID {
                Diagnostics.log("[TikTokCell] asset=\(id) updatePlayback: item.status=\(item.status.rawValue) not ready -> pause")
            }
            return
        }
        if UIApplication.shared.applicationState != .active {
            if let id = currentAssetID {
                Diagnostics.log("[TikTokCell] asset=\(id) updatePlayback: app not active -> pause")
            }
            player.pause()
            return
        }
        if isActive {
            if item.isPlaybackLikelyToKeepUp {
                if let id = currentAssetID {
                    Diagnostics.log("[TikTokCell] asset=\(id) updatePlayback: play (likelyToKeepUp=true)")
                }
                PlaybackRegistry.shared.willPlay(player)
                player.play()
            } else {
                if let id = currentAssetID {
                    Diagnostics.log("[TikTokCell] asset=\(id) updatePlayback: waiting (likelyToKeepUp=false) -> pause")
                }
                player.pause()
            }
        } else {
            if let id = currentAssetID {
                Diagnostics.log("[TikTokCell] asset=\(id) updatePlayback: cell inactive -> pause")
            }
            player.pause()
        }
    }

    private func applyItem(_ item: AVPlayerItem) {
        Diagnostics.log("[TikTokCell] applyItem: Applying AVPlayerItem to player. Asset ID: \(currentAssetID ?? "nil")")
        attachObservers(to: item)
        Diagnostics.signpostBegin("ApplyItemToReady", id: &spApplyToReady)
        Diagnostics.signpostBegin("ApplyItemToFirstFrame", id: &spApplyToFirstFrame)
        loadProbe?.markApplied()
        if let id = currentAssetID {
            Task { await NextVideoTraceCenter.shared.markApplied() }
            Task { await NextVideoTraceCenter.shared.markPath(.unknown) }
        }

        // HDR diagnostics + policy
        let hdr = extractHDRInfo(from: item.asset)
        Diagnostics.log(String(format: "[TikTokCell] HDR diag on applyItem: prim=%@ xfer=%@ ycbcr=%@ hasMD=%@ hasCLL=%@ isHLG=%@ isPQ=%@ isHDR=%@",
                               hdr.colorPrimaries ?? "nil",
                               hdr.transferFunction ?? "nil",
                               hdr.ycbcrMatrix ?? "nil",
                               hdr.hasMasteringDisplay ? "true" : "false",
                               hdr.hasContentLightLevel ? "true" : "false",
                               hdr.isHLG ? "true" : "false",
                               hdr.isPQ ? "true" : "false",
                               hdr.isHDR ? "true" : "false"))

        // Diagnostics.videoPerf("[VideoSummary] id=\(currentAssetID ?? "nil") \(videoSummary(for: item.asset))")

        computeAndLogVideoSummary(for: item)

        if #available(iOS 15.0, *), disableHDRMetadataEnabled, hdr.isHDR {
            Diagnostics.log("[TikTokCell] Disabling per-frame HDR display metadata (FeatureFlag) for asset ID: \(currentAssetID ?? "nil").")
            item.appliesPerFrameHDRDisplayMetadata = false
        }

        if sdrConversionEnabled, hdr.isHDR {
            Diagnostics.log("[TikTokCell] SDR conversion enabled and asset is HDR. Attempting to create and apply Rec.709 videoComposition for asset ID: \(currentAssetID ?? "nil").")
            if let vc = makeRec709VideoComposition(for: item.asset) {
                Diagnostics.log("[TikTokCell] Successfully created Rec.709 videoComposition. Applying to AVPlayerItem for asset ID: \(currentAssetID ?? "nil").")
                item.videoComposition = vc
            } else {
                Diagnostics.log("[TikTokCell] Failed to create Rec.709 composition for HDR asset ID: \(currentAssetID ?? "nil"). VideoComposition will NOT be applied.")
            }
        } else if hdr.isHDR {
            Diagnostics.log("[TikTokCell] HDR asset detected for asset ID: \(currentAssetID ?? "nil"), but SDR conversion is disabled or not applicable. Not applying SDR videoComposition.")
        }

        player.replaceCurrentItem(with: item)
        Diagnostics.log("[TikTokCell] replaceCurrentItem applied for asset ID: \(currentAssetID ?? "nil"). Player current item set.")
        if let id = currentAssetID {
            FirstLaunchProbe.shared.playerApplyItem(id: id)
        }
        item.preferredForwardBufferDuration = 2.0
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        hasPresentedFirstFrame = false
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] t in
            guard let self else { return }
            if !self.hasPresentedFirstFrame, t.seconds > 0 {
                Diagnostics.log("[TikTokCell] First frame presented for asset ID: \(self.currentAssetID ?? "nil") at time: \(t.seconds) tag=\(Diagnostics.shortTag(for: self.currentAssetID ?? ""))")
                self.hasPresentedFirstFrame = true
                self.loadProbe?.markFirstFrame()
                Task { await NextVideoTraceCenter.shared.markFirstFrame() }
                self.loadProbe?.finish(cancelled: false, failed: false)
                if let id = self.currentAssetID {
                    NotificationCenter.default.post(name: .playerFirstFrameDisplayed, object: nil, userInfo: ["id": id])
                }
                if let timeObserver = self.timeObserver {
                    self.player.removeTimeObserver(timeObserver)
                    self.timeObserver = nil
                }
                Diagnostics.signpostEnd("ApplyItemToFirstFrame", id: self.spApplyToFirstFrame)
                self.spApplyToFirstFrame = nil
            }
        }
        installDiagnostics(for: item)

        stallWatchdog?.cancel()
        isStalledFlag = false
        lastObservedTime = .zero
        lastAdvanceWall = CACurrentMediaTime()
        stallWatchdog = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let curItem = self.player.currentItem, curItem === item else { break }
                let now = CACurrentMediaTime()
                let curT = self.player.currentTime()
                let advanced = fabs(CMTimeGetSeconds(curT) - CMTimeGetSeconds(self.lastObservedTime)) > 0.03
                if advanced {
                    if self.isStalledFlag {
                        let stallDur = now - self.lastAdvanceWall
                        Diagnostics.log("[TikTokCell] stall END id=\(self.currentAssetID ?? "nil") dur=\(String(format: "%.2f", stallDur))s t=\(String(format: "%.2f", CMTimeGetSeconds(curT)))s tag=\(Diagnostics.shortTag(for: self.currentAssetID ?? ""))")
                        Diagnostics.signpostEnd("PlaybackStall", id: self.spPlaybackStall)
                        self.spPlaybackStall = nil
                        self.loadProbe?.stallEnded()
                        Task { await NextVideoTraceCenter.shared.stallEnded() }
                    }
                    self.isStalledFlag = false
                    self.lastAdvanceWall = now
                    self.lastObservedTime = curT
                    continue
                }
                let since = now - self.lastAdvanceWall
                let shouldBePlaying = self.isActive && UIApplication.shared.applicationState == .active && curItem.status == .readyToPlay
                if since > 1.0 && shouldBePlaying && !self.isStalledFlag {
                    let reason = self.player.reasonForWaitingToPlay?.rawValue ?? "nil"
                    let likely = curItem.isPlaybackLikelyToKeepUp
                    let empty = curItem.isPlaybackBufferEmpty
                    let full = curItem.isPlaybackBufferFull
                    let ranges = curItem.loadedTimeRanges.compactMap { $0.timeRangeValue }
                        .map { r in "[\(String(format: "%.2f", CMTimeGetSeconds(r.start)))..+\(String(format: "%.2f", CMTimeGetSeconds(r.duration)))]" }
                        .joined(separator: ", ")
                    Diagnostics.log("[TikTokCell] stall DETECTED id=\(self.currentAssetID ?? "nil") since=\(String(format: "%.2f", since))s status=\(curItem.status.rawValue) reason=\(reason) likely=\(likely) empty=\(empty) full=\(full) loaded=\(ranges)")
                    self.isStalledFlag = true
                    Diagnostics.signpostBegin("PlaybackStall", id: &self.spPlaybackStall)
                    self.loadProbe?.stallBegan()
                    Task { await NextVideoTraceCenter.shared.stallBegan() }
                }
            }
        }

        #if DEBUG
        if let out = videoOutput, player.currentItem !== item {
            item.remove(out)
            videoOutput = nil
        }
        if videoOutput == nil {
            let attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            let out = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
            item.add(out)
            videoOutput = out
        }
        renderWatchdog?.cancel()
        lastRenderedWall = CACurrentMediaTime()
        renderWatchdog = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastTime = self.player.currentTime()
            var lastHadFrame = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let curItem = self.player.currentItem, curItem === item, let out = self.videoOutput else { break }
                var itemTime = CMTime.invalid
                let hasNew = out.hasNewPixelBuffer(forItemTime: itemTime)
                let now = CACurrentMediaTime()
                let curT = self.player.currentTime()
                let timeAdvanced = fabs(CMTimeGetSeconds(curT) - CMTimeGetSeconds(lastTime)) > 0.03
                if hasNew {
                    lastRenderedWall = now
                }
                if timeAdvanced, !hasNew, self.player.timeControlStatus == .playing, UIApplication.shared.applicationState == .active, curItem.status == .readyToPlay {
                    let since = now - lastRenderedWall
                    if since > 1.0, lastHadFrame {
                        Diagnostics.log("[TikTokCell] RENDER stall DETECTED id=\(self.currentAssetID ?? "nil") since=\(String(format: "%.2f", since))s t=\(String(format: "%.2f", CMTimeGetSeconds(curT)))s")
                    }
                }
                lastHadFrame = hasNew || lastHadFrame
                lastTime = curT
            }
        }
        #endif
    }

    private func loadAsset(_ asset: PHAsset) async {
        // try prefetched AVPlayerItem first for fastest ready path
        if let item = await PlayerItemPrefetcher.shared.item(for: asset.localIdentifier, timeout: .milliseconds(800)) {
            loadProbe?.markPath(.prefetchedItem)
            Task { await NextVideoTraceCenter.shared.markPath(.prefetchedItem) }
            diagProbe?.startPhase("TikTok_UsePrefetchedItem")
            diagProbe?.attach(item: item)
            applyItem(item)
            diagProbe?.endPhase("TikTok_UsePrefetchedItem")
            return
        }

        if let warm = await VideoPrefetcher.shared.asset(for: asset.localIdentifier, timeout: .milliseconds(450)) {
            loadProbe?.markPath(.prefetchedAsset)
            Task { await NextVideoTraceCenter.shared.markPath(.prefetchedAsset) }
            diagProbe?.startPhase("TikTok_UsePrefetchedAsset")
            let item = AVPlayerItem(asset: warm)
            diagProbe?.attach(item: item)
            applyItem(item)
            diagProbe?.endPhase("TikTok_UsePrefetchedAsset")
            FirstLaunchProbe.shared.playerUsedPrefetch(id: asset.localIdentifier)
            return
        }

        loadProbe?.markPath(.directRequest)
        Task { await NextVideoTraceCenter.shared.markPath(.directRequest) }

        diagProbe?.startPhase("TikTok_RequestPlayerItem")
        Diagnostics.log("[TikTokCell] requestPlayerItem begin id=\(asset.localIdentifier) onMain=\(Thread.isMainThread)")
        FirstLaunchProbe.shared.playerRequestBegin(id: asset.localIdentifier)
        loadProbe?.markRequestStart()
        Task { await NextVideoTraceCenter.shared.markRequestStart() }

        let (item, info) = await PlayerItemBootstrapper.shared.awaitResult(asset: asset)

        Task { await NextVideoTraceCenter.shared.markRequestEnd(info: info) }
        loadProbe?.markRequestEnd(info: info)
        let dt = CACurrentMediaTime() - self.diagStart
        Diagnostics.log("TikTokCell requestPlayerItem finished in \(String(format: "%.3f", dt))s")
        PhotoKitDiagnostics.logResultInfo(prefix: "TikTokCell request info", info: info)
        if let info {
            let inCloud = (info[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue ?? false
            let cancelled = (info[PHImageCancelledKey] as? NSNumber)?.boolValue ?? false
            let err = (info[PHImageErrorKey] as? NSError)?.localizedDescription
            FirstLaunchProbe.shared.playerRequestInfo(id: asset.localIdentifier, inCloud: inCloud, cancelled: cancelled, errorDesc: err)
        } else {
            FirstLaunchProbe.shared.playerRequestInfo(id: asset.localIdentifier, inCloud: false, cancelled: false, errorDesc: nil)
        }
        diagProbe?.endPhase("TikTok_RequestPlayerItem")

        guard !Task.isCancelled else {
            if let id = currentAssetID {
                Task { await NextVideoTraceCenter.shared.finish(cancelled: true, failed: false) }
            }
            return
        }
        if let item {
            diagProbe?.attach(item: item)
            applyItem(item)
        } else {
            Diagnostics.log("[TikTokCell] requestPlayerItem returned nil item")
            loadProbe?.finish(failed: true)
            if let id = currentAssetID {
                Task { await NextVideoTraceCenter.shared.finish(cancelled: false, failed: true) }
            }
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
            let musicPlaying: Bool = FeatureFlags.enableAppleMusicIntegration ? MusicCenter.shared.isPlaying : false
            let effective: Float = musicPlaying ? min(base, VideoVolumeManager.shared.duckingCapWhileMusic) : base
            self.player.volume = effective
        }
    }

    private func applySongIfAny() {
        songOverrideTask?.cancel()
        songOverrideTask = nil

        guard isActive else {
            Diagnostics.log("AM applySongIfAny skip (inactive). Leaving any managed playback running.")
            return
        }

        guard FeatureFlags.enableAppleMusicIntegration else {
            appliedSongID = nil
            return
        }

        guard let id = currentAssetID else {
            Diagnostics.log("AM applySongIfAny no currentAssetID. Leaving any managed playback running.")
            return
        }

        let requestID = id
        songOverrideTask = Task { [weak self] in
            guard let self else { return }
            let ref = await VideoAudioOverrides.shared.songReference(for: requestID)
            Diagnostics.log("AM applySongIfAny id=\(requestID) ref=\(ref?.debugKey ?? "nil") isActive=\(self.isActive) hasFirst=\(self.hasPresentedFirstFrame)")
            guard !Task.isCancelled else { return }

            if ref != nil {
                let t0 = CACurrentMediaTime()
                let maxWait: CFTimeInterval = 1.8
                var waited: CFTimeInterval = 0
                Diagnostics.log("AM Gate: deferring start id=\(requestID) until first frame/steady play or \(String(format: "%.1f", maxWait))s")
                while !Task.isCancelled, waited < maxWait {
                    let satisfied: Bool = await MainActor.run { [weak self] in
                        guard let self else { return false }
                        guard self.isActive, self.currentAssetID == requestID else { return false }
                        let ready = self.player.currentItem?.status == .readyToPlay
                        let playing = self.player.timeControlStatus == .playing
                        let recentAdvance = (CACurrentMediaTime() - self.lastAdvanceWall) < 0.4 && self.lastAdvanceWall > 0
                        return self.hasPresentedFirstFrame && ready && playing && recentAdvance
                    }
                    if satisfied { break }
                    try? await Task.sleep(for: .milliseconds(50))
                    waited = CACurrentMediaTime() - t0
                }
                let hasFirst = await MainActor.run { [weak self] in self?.hasPresentedFirstFrame ?? false }
                Diagnostics.log("AM Gate: proceed id=\(requestID) waited=\(String(format: "%.3f", waited))s hasFirst=\(hasFirst)")
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.isActive, self.currentAssetID == requestID else {
                    Diagnostics.log("AM Gate: skip (inactive or asset changed) id=\(requestID)")
                    return
                }
                self.updateAppleMusicPlayback(reference: ref)
            }
        }
    }

    @MainActor
    private func updateAppleMusicPlayback(reference: SongReference?) {
        guard FeatureFlags.enableAppleMusicIntegration else {
            appliedSongID = nil
            return
        }

        let now = CACurrentMediaTime()
        let storeID = reference?.appleMusicStoreID
        if let s = storeID, lastAMAttemptStoreID == s, (now - lastAMAttemptAt) < 5 {
            Diagnostics.log("UpdateAM cooldown skip storeID=\(s) dt=\(String(format: "%.2f", now - lastAMAttemptAt))s appliedSongID=\(appliedSongID ?? "nil")")
            return
        }

        Diagnostics.signpostBegin("AppleMusicFeatureStart", id: &spAppleMusic)
        let beforeID = AppleMusicController.shared.managedNowPlayingStoreID() ?? "nil"

        if let reference {
            if let s = reference.appleMusicStoreID {
                lastAMAttemptStoreID = s
                lastAMAttemptAt = now
            }
            if let s = reference.appleMusicStoreID, appliedSongID == s {
                Diagnostics.log("UpdateAM same storeID=\(s) -> resumeIfManaged; nowPlaying(before)=\(beforeID)")
                if AppleMusicController.shared.hasActiveManagedPlayback {
                    AppleMusicController.shared.resumeIfManaged()
                } else {
                    AppleMusicController.shared.play(reference: reference)
                }
                startAMVerify(expectedStoreID: reference.appleMusicStoreID, reason: "resume-or-play-same")
            } else {
                Diagnostics.log("UpdateAM play reference=\(reference.debugKey) appliedSongID(before)=\(appliedSongID ?? "nil") nowPlaying(before)=\(beforeID)")
                AppleMusicController.shared.play(reference: reference)
                appliedSongID = reference.appleMusicStoreID
                startAMVerify(expectedStoreID: reference.appleMusicStoreID, reason: "play-reference")
            }
        } else {
            Diagnostics.log("UpdateAM no reference -> keep current managed playback (beforeNowPlaying=\(beforeID))")
            // Keep playing the current managed track; do not clear appliedSongID; no verification needed.
        }

        let afterID = AppleMusicController.shared.managedNowPlayingStoreID() ?? "nil"
        Diagnostics.log("UpdateAM after call nowPlaying=\(afterID) expected=\(storeID ?? "nil") appliedSongID=\(appliedSongID ?? "nil")")
        Diagnostics.signpostEnd("AppleMusicFeatureStart", id: spAppleMusic)
        spAppleMusic = nil
    }

    private func startAMVerify(expectedStoreID: String?, reason: String) {
        amVerifyTask?.cancel()
        amVerifyTask = Task { [weak self] in
            guard let self else { return }
            let checkpoints: [UInt64] = [250, 600, 1200] // ms
            for (idx, ms) in checkpoints.enumerated() {
                try? await Task.sleep(for: .milliseconds(ms))
                let current = AppleMusicController.shared.managedNowPlayingStoreID()
                let ok: Bool = (expectedStoreID == nil) ? (current == nil) : (current == expectedStoreID)
                Diagnostics.log(String(format: "AM Verify[%d] reason=%@ expected=%@ nowPlaying=%@ match=%@ asset=%@",
                                       idx,
                                       reason,
                                       expectedStoreID ?? "nil",
                                       current ?? "nil",
                                       ok ? "true" : "false",
                                       self.currentAssetID ?? "nil"))
            }
        }
    }

    private func installDiagnostics(for item: AVPlayerItem) {
        let id = currentAssetID ?? "nil"
        dumpAssetDiagnostics(asset: item.asset, id: id)
        accessLogObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemNewAccessLogEntry, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            if let e = item.accessLog()?.events.last {
                Diagnostics.log("[TikTokCell] accessLog id=\(id) segments=\(e.numberOfMediaRequests) observedBr=\(String(format: "%.0f", e.observedBitrate)) indicatedBr=\(String(format: "%.0f", e.indicatedBitrate)) transferred=\(e.numberOfBytesTransferred)")
            } else {
                Diagnostics.log("[TikTokCell] accessLog id=\(id) (no events)")
            }
        }
        errorLogObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemNewErrorLogEntry, object: item, queue: .main) { _ in
            if let e = item.errorLog()?.events.last {
                Diagnostics.log("[TikTokCell] errorLog domain=\(e.errorDomain) code=\(e.errorStatusCode) server=\(e.serverAddress ?? "nil") uri=\(e.uri ?? "nil")")
            }
        }

        // These are owned by attachObservers(to:) to avoid duplicate logs and lifetimes.
    }

    private func dumpAssetDiagnostics(asset: AVAsset, id: String) {
        let kind = String(describing: type(of: asset))
        if let urlAsset = asset as? AVURLAsset {
            let url = urlAsset.url
            Diagnostics.log("[TikTokCell] assetDiag id=\(id) kind=\(kind) urlScheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil") path=\(url.lastPathComponent)")
            if url.isFileURL {
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                    let size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
                    Diagnostics.log("[TikTokCell] assetDiag file exists size=\(size)")
                } catch {
                    Diagnostics.log("[TikTokCell] assetDiag file check error=\(String(describing: error))")
                }
            }
        } else {
            Diagnostics.log("[TikTokCell] assetDiag id=\(id) kind=\(kind)")
        }

        let hdr = extractHDRInfo(from: asset)
        Diagnostics.log(String(format: "[TikTokCell] assetHDR id=%@ prim=%@ xfer=%@ ycbcr=%@ hasMD=%@ hasCLL=%@ isHLG=%@ isPQ=%@ isHDR=%@",
                               id,
                               hdr.colorPrimaries ?? "nil",
                               hdr.transferFunction ?? "nil",
                               hdr.ycbcrMatrix ?? "nil",
                               hdr.hasMasteringDisplay ? "true" : "false",
                               hdr.hasContentLightLevel ? "true" : "false",
                               hdr.isHLG ? "true" : "false",
                               hdr.isPQ ? "true" : "false",
                               hdr.isHDR ? "true" : "false"))

        asset.loadValuesAsynchronously(forKeys: ["playable", "tracks", "duration"]) {
            Task { @MainActor in
                let keys = ["playable", "tracks", "duration"]
                for k in keys {
                    var err: NSError?
                    let st = asset.statusOfValue(forKey: k, error: &err)
                    Diagnostics.log("[TikTokCell] assetKey id=\(id) \(k)=\(st.rawValue) err=\(String(describing: err?.localizedDescription))")
                }
                FirstLaunchProbe.shared.playerAssetKeysLoaded(id: id)
            }
        }
    }
}