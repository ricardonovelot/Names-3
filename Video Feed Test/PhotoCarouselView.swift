import SwiftUI
import Photos
import UIKit

struct PhotoCarouselPostView: View {
    let assets: [PHAsset]
    @State private var page: Int = 0
    
    var body: some View {
        ZStack {
            TabView(selection: $page) {
                ForEach(Array(assets.enumerated()), id: \.1.localIdentifier) { idx, asset in
                    PhotoSlideView(asset: asset)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            VStack {
                Spacer()
                if assets.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<assets.count, id: \.self) { i in
                            Circle()
                                .fill(i == page ? Color.white : Color.white.opacity(0.35))
                                .frame(width: i == page ? 8 : 6, height: i == page ? 8 : 6)
                        }
                    }
                    .padding(.bottom, 28)
                }
            }
        }
        .background(Color.black)
        .onAppear {
            Diagnostics.log("PhotoCarousel appear count=\(assets.count) first=\(assets.first?.localIdentifier ?? "n/a")")
        }
    }
}

private struct PhotoSlideView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var task: Task<Void, Never>?
    
    var body: some View {
        GeometryReader { geo in
            let horizontalPadding: CGFloat = 16
            let maxHeightFraction: CGFloat = 0.70
            let corner: CGFloat = 14
            let maxW = max(0, geo.size.width - horizontalPadding * 2)
            let maxH = max(0, geo.size.height * maxHeightFraction)
            
            ZStack {
                if let image {
                    VStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: maxW, maxHeight: maxH)
                            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                            .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, horizontalPadding)
                    .accessibilityHidden(true)
                } else {
                    VStack {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .frame(maxWidth: maxW, maxHeight: maxH)
                            .overlay(
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, horizontalPadding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onAppear {
                let scale = UIScreen.main.scale
                let viewportPx = CGSize(width: maxW * scale, height: maxH * scale)
                let clampedPx = CGSize(
                    width: min(viewportPx.width, CGFloat(asset.pixelWidth)),
                    height: min(viewportPx.height, CGFloat(asset.pixelHeight))
                )
                startLoading(targetSize: clampedPx)
            }
            .onDisappear {
                cancelLoading()
            }
        }
    }
    
    private func startLoading(targetSize: CGSize) {
        cancelLoading()
        task = Task { @MainActor in
            let stream = ImagePrefetcher.shared.progressiveImage(for: asset, targetSize: targetSize)
            for await (img, _) in stream {
                if Task.isCancelled { break }
                self.image = img
            }
        }
    }
    
    private func cancelLoading() {
        task?.cancel()
        task = nil
    }
}