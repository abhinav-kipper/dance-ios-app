import SwiftUI
import AVFoundation
import RepasoCore

/// A muted, looping preview of a short range of a video. Fades in once its first frame is ready, so the
/// poster underneath never flashes black.
struct LivePreviewView: UIViewRepresentable {
    let source: PreviewSource
    let url: URL

    func makeUIView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.start(url: url, range: source.range)
        return view
    }

    func updateUIView(_ view: PreviewLayerView, context: Context) {}

    static func dismantleUIView(_ view: PreviewLayerView, coordinator: ()) {
        view.stop()
    }

    final class PreviewLayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }   // guaranteed by layerClass
        private var looper: AVPlayerLooper?
        private var readyObservation: NSKeyValueObservation?

        func start(url: URL, range: ClosedRange<Double>) {
            alpha = 0
            isUserInteractionEnabled = false
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.allowsExternalPlayback = false
            let timeRange = CMTimeRange(start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                                        end: CMTime(seconds: range.upperBound, preferredTimescale: 600))
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url), timeRange: timeRange)
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.player = player
            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                Task { @MainActor in
                    UIView.animate(withDuration: 0.25) { self?.alpha = 1 }
                }
            }
            player.play()
        }

        func stop() {
            readyObservation = nil
            looper?.disableLooping()
            playerLayer.player?.pause()
            playerLayer.player = nil
            looper = nil
        }
    }
}
