import SwiftUI
import AVFoundation
import UIKit

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private var readyObs: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        Diagnostics.log("PlayerLayerView init")
        readyObs = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard let self else { return }
            #if DEBUG
            Diagnostics.log("PlayerLayer isReadyForDisplay=\(layer.isReadyForDisplay) videoRect=\(NSCoder.string(for: layer.videoRect)) bounds=\(NSCoder.string(for: self.bounds))")
            #endif
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        Diagnostics.log("PlayerLayerView init(coder:)")
        readyObs = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard let self else { return }
            #if DEBUG
            Diagnostics.log("PlayerLayer isReadyForDisplay=\(layer.isReadyForDisplay) videoRect=\(NSCoder.string(for: layer.videoRect)) bounds=\(NSCoder.string(for: self.bounds))")
            #endif
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        Diagnostics.log("PlayerLayerView didMoveToWindow window=\(self.window != nil)")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        #if DEBUG
        Diagnostics.log("PlayerLayerView layoutSubviews bounds=\(NSCoder.string(for: bounds)) videoRect=\(NSCoder.string(for: playerLayer.videoRect)) ready=\(playerLayer.isReadyForDisplay)")
        #endif
    }
}

struct PlayerLayerContainer: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill
    
    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.backgroundColor = .black
        v.playerLayer.player = player
        v.playerLayer.videoGravity = videoGravity
        Diagnostics.log("PlayerLayerContainer makeUIView player=\(Unmanaged.passUnretained(player).toOpaque()) gravity=\(videoGravity.rawValue)")
        return v
    }
    
    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player {
            Diagnostics.log("PlayerLayerContainer updateUIView swap player old=\(String(describing: uiView.playerLayer.player)) new=\(Unmanaged.passUnretained(player).toOpaque())")
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            Diagnostics.log("PlayerLayerContainer updateUIView gravity=\(videoGravity.rawValue)")
            uiView.playerLayer.videoGravity = videoGravity
        }
    }
}