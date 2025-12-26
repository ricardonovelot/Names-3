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

    @State private var placeholderImage: UIImage?
    @State private var placeholderRequestID: PHImageRequestID = PHInvalidImageRequestID
    @State private var showPlaceholder: Bool = true
    @State private var placeholderTask: Task<Void, Never>?

    private var isPortrait: Bool {
        asset.pixelHeight >= asset.pixelWidth
    }
    private var playerVideoGravity: AVLayerVideoGravity {
//        if noCropMode {
//            return .resizeAspect
//        }
        return .resizeAspectFill
    }

    var body: some View {
        ZStack {
            PlayerLayerContainer(player: controller.player, videoGravity: playerVideoGravity)
                .ignoresSafeArea()
//            if showPlaceholder {
//                Group {
//                    if let img = placeholderImage {
//                        if noCropMode {
//                            Image(uiImage: img)
//                                .resizable()
//                                .scaledToFit()
//                                .background(Color.black)
//                                .ignoresSafeArea()
//                        } else {
//                            Image(uiImage: img)
//                                .resizable()
//                                .scaledToFill()
//                                .ignoresSafeArea()
//                        }
//                    } else {
//                        ProgressView()
//                            .tint(.white)
//                            .scaleEffect(1.2)
//                    }
//                }
//            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isActive {
                controller.togglePlay()
            }
        }
        .onAppear {
            Diagnostics.log("TikTokPlayerView onAppear for asset=\(asset.localIdentifier) isActive=\(isActive)")
            showPlaceholder = true
            requestPlaceholder()
            controller.setAsset(asset)
            controller.setActive(isActive)
            if isActive {
                CurrentPlayback.shared.currentAssetID = asset.localIdentifier
            }
        }
        .onDisappear {
            Diagnostics.log("TikTokPlayerView onDisappear for asset=\(asset.localIdentifier)")
            cancelPlaceholderRequest()
            controller.cancel()
        }
        .onChange(of: isActive) { newValue in
            Diagnostics.log("TikTokPlayerView isActive changed asset=\(asset.localIdentifier) -> \(newValue)")
            controller.setActive(newValue)
            if newValue {
                CurrentPlayback.shared.currentAssetID = asset.localIdentifier
            }
        }
        .onChange(of: controller.hasPresentedFirstFrame) { hasFirst in
            if hasFirst {
                withAnimation(.easeOut(duration: 0.2)) {
                    showPlaceholder = false
                }
                cancelPlaceholderRequest()
            }
        }
    }

    private func requestPlaceholder() {
        cancelPlaceholderRequest()
        placeholderTask = Task { @MainActor in
            var producedExactFirstFrame = false
            if let av = await VideoPrefetcher.shared.assetIfCached(asset.localIdentifier) {
                let gen = AVAssetImageGenerator(asset: av)
                gen.appliesPreferredTrackTransform = true
                gen.requestedTimeToleranceBefore = .zero
                gen.requestedTimeToleranceAfter = .zero
                let maxDim = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
                gen.maximumSize = CGSize(width: maxDim, height: maxDim)
                if let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) {
                    self.placeholderImage = UIImage(cgImage: cg)
                    producedExactFirstFrame = true
                }
            }

            if producedExactFirstFrame {
                return
            }

            let screenPx = UIScreen.main.nativeBounds.size
            let upscalePx = CGSize(width: floor(screenPx.width * 1.25), height: floor(screenPx.height * 1.25))
            let targetPx = CGSize(width: min(upscalePx.width, CGFloat(asset.pixelWidth)),
                                  height: min(upscalePx.height, CGFloat(asset.pixelHeight)))
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.resizeMode = .exact
            opts.isSynchronous = false
            opts.isNetworkAccessAllowed = true
            self.placeholderRequestID = PHImageManager.default().requestImage(for: asset,
                                                                              targetSize: targetPx,
                                                                              contentMode: .aspectFill,
                                                                              options: opts) { image, info in
                if let image {
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
                    if !isDegraded {
                        self.placeholderImage = image
                    }
                }
            }
        }
    }

    private func cancelPlaceholderRequest() {
        if placeholderRequestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(placeholderRequestID)
            placeholderRequestID = PHInvalidImageRequestID
        }
        placeholderTask?.cancel()
        placeholderTask = nil
    }
}
