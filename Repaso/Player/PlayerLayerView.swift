import SwiftUI
import AVFoundation

/// Hosts an `AVPlayerLayer` (aspect-fit, black background).
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: LayerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = gravity
    }

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }   // guaranteed by layerClass
    }
}
