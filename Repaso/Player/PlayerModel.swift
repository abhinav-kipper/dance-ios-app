import AVFoundation
import Observation
import RepasoCore

/// Plays one clip range of an original on a single reused AVPlayer, looping per `LoopController`.
@Observable @MainActor
final class PlayerModel {
    let player = AVPlayer()
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var restingSeconds: Double?
    private(set) var missingFile = false
    var loop = LoopController()
    var speed: Double = 1 {
        didSet { if isPlaying && restingSeconds == nil { player.rate = Float(speed) } }
    }

    private var range: ClosedRange<Double> = 0...1
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var restTask: Task<Void, Never>?

    init() {
        player.automaticallyWaitsToMinimizeStalling = false   // local files: start immediately
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated { self?.tick(seconds) }
        }
    }

    func load(_ clip: Clip, videos: VideoStore) {
        cancelRest()
        // Here, not in init: SwiftUI may build throwaway @State initial values on parent re-renders.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        // setActive can block; keep it off the main thread so tap-to-play stays instant.
        Task.detached(priority: .userInitiated) { try? AVAudioSession.sharedInstance().setActive(true) }
        guard let original = clip.original else {
            missingFile = true
            return
        }
        let url = videos.url(for: original.fileName)
        missingFile = !FileManager.default.fileExists(atPath: url.path)
        guard !missingFile else {
            player.replaceCurrentItem(with: nil)
            return
        }
        range = clip.start...clip.end
        progress = 0
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain   // slowed audio keeps its pitch
        item.forwardPlaybackEndTime = CMTime(seconds: clip.end, preferredTimescale: 600)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reachedEnd() }
        }
        player.replaceCurrentItem(with: item)
        isPlaying = true
        seekToStart(thenPlay: true)
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        cancelRest()
        isPlaying = true
        if progress >= 0.999 {
            seekToStart(thenPlay: true)
        } else {
            player.playImmediately(atRate: Float(speed))
        }
    }

    func pause() {
        cancelRest()
        player.pause()
        isPlaying = false
    }

    func toggleLoop() { loop.loopEnabled.toggle() }
    func cycleGap() { loop.cycleGap() }

    func tearDown() {
        pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    // MARK: Private

    private func reachedEnd() {
        switch loop.actionAtEnd() {
        case .restart:
            seekToStart(thenPlay: true)
        case .restartAfter(let seconds):
            player.pause()
            restingSeconds = seconds
            restTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard let self, !Task.isCancelled else { return }
                restingSeconds = nil
                seekToStart(thenPlay: true)
            }
        case .stop:
            player.pause()
            isPlaying = false
            progress = 1
        }
    }

    private func cancelRest() {
        restTask?.cancel()
        restTask = nil
        restingSeconds = nil
    }

    private func seekToStart(thenPlay: Bool) {
        let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor in self?.didSeek(thenPlay: thenPlay) }
        }
    }

    private func didSeek(thenPlay: Bool) {
        progress = 0
        if thenPlay && isPlaying { player.playImmediately(atRate: Float(speed)) }
    }

    private func tick(_ t: Double) {
        let length = range.upperBound - range.lowerBound
        guard length > 0, restingSeconds == nil else { return }
        progress = min(1, max(0, (t - range.lowerBound) / length))
    }
}
