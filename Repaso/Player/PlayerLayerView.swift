import SwiftUI
import AVFoundation

/// Hosts an `AVPlayerLayer` (aspect-fit, black background) and reports when it has a frame to show.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    /// Called with `isReadyForDisplay`: false right after the item changes, true once its first frame is up.
    var onReadyForDisplay: ((Bool) -> Void)?

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        view.backgroundColor = .black
        view.onReady = onReadyForDisplay
        view.startObserving()
        return view
    }

    func updateUIView(_ uiView: LayerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = gravity
        uiView.onReady = onReadyForDisplay
    }

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }   // guaranteed by layerClass
        var onReady: ((Bool) -> Void)?
        private var observation: NSKeyValueObservation?

        func startObserving() {
            observation = Self.observeReady(playerLayer) { [weak self] ready in
                Task { @MainActor in self?.onReady?(ready) }
            }
        }

        /// Built outside the main actor: KVO may call back on any thread.
        nonisolated private static func observeReady(_ layer: AVPlayerLayer,
                                                     report: @escaping @Sendable (Bool) -> Void) -> NSKeyValueObservation {
            layer.observe(\.isReadyForDisplay, options: [.new]) { layer, _ in report(layer.isReadyForDisplay) }
        }
    }
}
