import SwiftUI
import AVFoundation
import Photos
import UIKit

struct TikTokPlayerView: View {
    let asset: PHAsset
    let isActive: Bool
    let pinnedMode: Bool
    let noCropMode: Bool
    @StateObject private var controller = SingleAssetPlayer()

    private var isPortrait: Bool {
        asset.pixelHeight >= asset.pixelWidth
    }
    private var playerVideoGravity: AVLayerVideoGravity {
        return .resizeAspectFill
    }

    var body: some View {
        ZStack {
            PlayerLayerContainer(player: controller.player, videoGravity: playerVideoGravity)
                .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isActive {
                controller.togglePlay()
            }
        }
        .onAppear {
            Diagnostics.log("TikTokPlayerView onAppear for asset=\(asset.localIdentifier) isActive=\(isActive)")
            controller.setAsset(asset)
            controller.setActive(isActive)
            if isActive {
                CurrentPlayback.shared.currentAssetID = asset.localIdentifier
            }
        }
        .onDisappear {
            Diagnostics.log("TikTokPlayerView onDisappear for asset=\(asset.localIdentifier)")
            controller.cancel()
        }
        .onChange(of: isActive) { _, newValue in
            Diagnostics.log("TikTokPlayerView isActive changed asset=\(asset.localIdentifier) -> \(newValue)")
            controller.setActive(newValue)
            if newValue {
                CurrentPlayback.shared.currentAssetID = asset.localIdentifier
            }
        }
        .onChange(of: controller.hasPresentedFirstFrame) { old, hasFirst in
            if !old, hasFirst {
                Diagnostics.log("TikTokPlayerView first frame displayed asset=\(asset.localIdentifier)")
                NotificationCenter.default.post(name: .playerFirstFrameDisplayed, object: nil, userInfo: ["id": asset.localIdentifier])
                FirstLaunchProbe.shared.firstFrameDisplayed(id: asset.localIdentifier)
                Task { await PhaseGate.shared.mark(.firstVideoReady) }
            }
        }
    }
}