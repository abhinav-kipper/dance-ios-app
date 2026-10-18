import AVFoundation

/// A whole recording playing on a loop with sound, for the guide's first step.
@MainActor
final class LoopingVideo {
    let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL) {
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
    }

    func play() {
        Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        player.play()
    }

    func pause() { player.pause() }
}
