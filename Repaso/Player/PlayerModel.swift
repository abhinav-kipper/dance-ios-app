import AVFoundation
import Observation
import RepasoCore

/// Plays one clip range of a recording on a single reused AVPlayer, looping per `LoopController`.
@Observable @MainActor
final class PlayerModel {
    let player = AVPlayer()
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var restingSeconds: Double?
    private(set) var missingFile = false
    /// Playhead in seconds within the recording, and the video's frame rate, for frame stepping.
    private(set) var currentTime: Double = 0
    private(set) var frameRate: Double = 30
    var loop = LoopController()
    var speed: Double = 1 {
        didSet { if isPlaying && restingSeconds == nil { player.rate = playbackRate } }
    }
    /// Hold-to-step in progress: the side of the video being held.
    private(set) var holdZone: HoldSeek.Zone = .none
    private var holdTask: Task<Void, Never>?
    /// Dragging the timeline: the line follows the finger and seeks are chained so the latest position always wins.
    private(set) var isScrubbing = false
    private var scrubResume = false
    private var scrubSeekInFlight = false
    private var pendingScrubTime: Double?

    private var playbackRate: Float { Float(speed) }

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
        // Both calls can block, so they stay off the main thread and tap-to-play stays instant.
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
        }
        guard let recording = clip.recording else {
            missingFile = true
            return
        }
        let url = videos.url(for: recording.fileName)
        missingFile = !FileManager.default.fileExists(atPath: url.path)
        guard !missingFile else {
            player.replaceCurrentItem(with: nil)
            return
        }
        range = clip.range
        progress = 0
        currentTime = range.lowerBound
        let asset = AVURLAsset(url: url)
        Task { [weak self] in
            let rate = try? await asset.loadTracks(withMediaType: .video).first?.load(.nominalFrameRate)
            if let rate, rate > 0 { self?.frameRate = Double(rate) }
        }
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.audioTimePitchAlgorithm = .timeDomain   // slowed audio keeps its pitch
        playerItem.forwardPlaybackEndTime = CMTime(seconds: range.upperBound, preferredTimescale: 600)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reachedEnd() }
        }
        player.replaceCurrentItem(with: playerItem)
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
            player.playImmediately(atRate: playbackRate)
        }
    }

    func pause() {
        cancelRest()
        player.pause()
        isPlaying = false
    }

    var frameIndex: Int { Int((currentTime * frameRate).rounded()) }

    /// Seconds into the clip (or video) being played.
    var positionInItem: Double { max(0, currentTime - range.lowerBound) }
    var itemLength: Double { range.upperBound - range.lowerBound }
    /// Direction of the last frame step: +1 forward, −1 back.
    private(set) var lastStepDirection = 0

    var canStep: Bool { player.currentItem?.canStepForward == true && player.currentItem?.canStepBackward == true }

    /// Steps `count` frames (negative = back), pausing first and staying inside the clip.
    func step(by count: Int) {
        guard count != 0, let item = player.currentItem else { return }
        if isPlaying { pause() }
        let now = player.currentTime().seconds
        guard now.isFinite else { return }
        let first = Int(((range.lowerBound - now) * frameRate).rounded(.up))
        let last = Int(((range.upperBound - now) * frameRate).rounded(.down)) - 1
        let allowed = min(max(count, first), max(first, last))
        guard allowed != 0 else { return }
        lastStepDirection = allowed > 0 ? 1 : -1
        item.step(byCount: allowed)
        let after = player.currentTime().seconds
        if after.isFinite { currentTime = after }
        let length = range.upperBound - range.lowerBound
        if length > 0 { progress = min(1, max(0, (currentTime - range.lowerBound) / length)) }
    }

    // MARK: Hold to step frames

    /// Holding a side pauses and steps one frame at a time in that direction until released.
    func beginHold(_ zone: HoldSeek.Zone) {
        let direction = HoldSeek.frameStep(for: zone)
        guard direction != 0, holdZone == .none, canStep else { return }
        cancelRest()
        holdZone = zone
        pause()
        holdTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                self.step(by: direction)   // clamps to the clip, so it simply stops at either end
                try? await Task.sleep(for: .seconds(HoldSeek.frameInterval))
            }
        }
    }

    /// Letting go stays paused on the frame reached, so the position can be studied.
    func endHold() {
        guard holdZone != .none else { return }
        holdTask?.cancel()
        holdTask = nil
        holdZone = .none
    }

    // MARK: Scrubbing

    func beginScrub() {
        guard !isScrubbing else { return }
        scrubResume = isPlaying
        pause()
        isScrubbing = true
    }

    /// Moves the playhead to `fraction` of the clip (0…1), showing exact frames as fast as the decoder allows.
    func scrub(to fraction: Double) {
        guard fraction.isFinite else { return }
        let f = min(max(0, fraction), 1)
        progress = f
        currentTime = range.lowerBound + f * itemLength
        pendingScrubTime = currentTime
        seekToPendingScrub()
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        if scrubResume { play() }
        scrubResume = false
    }

    private func seekToPendingScrub() {
        guard !scrubSeekInFlight, let t = pendingScrubTime else { return }
        pendingScrubTime = nil
        scrubSeekInFlight = true
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.scrubSeekInFlight = false
                self?.seekToPendingScrub()
            }
        }
    }


    func tearDown() {
        holdTask?.cancel()
        holdTask = nil
        holdZone = .none
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
        if thenPlay && isPlaying { player.playImmediately(atRate: playbackRate) }
    }

    private func tick(_ t: Double) {
        guard t.isFinite, !isScrubbing else { return }   // NaN while seeking or switching to AirPlay
        currentTime = t
        let length = range.upperBound - range.lowerBound
        guard length > 0, restingSeconds == nil else { return }
        progress = min(1, max(0, (t - range.lowerBound) / length))
    }
}
