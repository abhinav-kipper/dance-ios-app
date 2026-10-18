import AVFoundation
import Observation
import RepasoCore

/// Playback, mark state and filmstrip frames for Cut mode.
@Observable @MainActor
final class CutModel {
    let player = AVPlayer()
    let duration: Double
    private(set) var time: Double = 0
    private(set) var isPlaying = false
    private(set) var missingFile = false
    var session: CutSession
    var selectedID: UUID?
    /// Live range while a trim handle is dragged (saved on release).
    var draftRange: ClosedRange<Double>?
    /// Seconds across the filmstrip; pinching the strip changes it.
    var visibleSeconds: Double
    /// The strip is being scrolled or a handle dragged: the video follows the finger, not the other way round.
    private(set) var isScrubbing = false

    private let videoURL: URL
    private var tileCache: [String: CGImage] = [:]
    private var timeObserver: Any?
    private var scrubResume = false
    /// Smooth scrubbing (Apple QA1820): one seek at a time, always to the newest target, so frames keep coming
    /// while the finger moves instead of every seek cancelling the one before.
    private var seekInFlight = false
    private var pendingSeek: (time: Double, precise: Bool)?

    init(recording: Recording, videos: VideoStore) {
        duration = recording.duration
        session = CutSession(duration: recording.duration)
        visibleSeconds = CutStrip.clampVisible(CutStrip.defaultVisible, duration: recording.duration)
        videoURL = videos.url(for: recording.fileName)
        missingFile = !FileManager.default.fileExists(atPath: videoURL.path)
        player.automaticallyWaitsToMinimizeStalling = false
        if !missingFile {
            let item = AVPlayerItem(url: videoURL)
            item.audioTimePitchAlgorithm = .timeDomain
            player.replaceCurrentItem(with: item)
        }
        // Off the main thread: setCategory can block while another player holds the session.
        Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        }
        // 60 Hz, so the strip glides with playback rather than stepping after it.
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60), queue: .main) { [weak self] t in
            let seconds = t.seconds
            MainActor.assumeIsolated { self?.tick(seconds) }
        }
    }

    // MARK: Transport

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard !missingFile else { return }
        if time >= duration - 0.05 { seek(0) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    /// Moves to `t`. While dragging (`precise: false`) a frame's slack lets the decoder keep up; settling is exact.
    func seek(_ t: Double, precise: Bool = true) {
        guard t.isFinite else { return }
        let clamped = min(max(0, t), duration)
        time = clamped
        pendingSeek = (clamped, precise)
        if !seekInFlight { startNextSeek() }
    }

    private func startNextSeek() {
        guard let next = pendingSeek else { return }
        pendingSeek = nil
        seekInFlight = true
        let tolerance = next.precise ? CMTime.zero : CMTime(value: 1, timescale: 30)
        player.seek(to: CMTime(seconds: next.time, preferredTimescale: 600),
                    toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seekInFlight = false
                self.startNextSeek()
            }
        }
    }

    func beginScrub() {
        guard !isScrubbing else { return }
        isScrubbing = true
        scrubResume = isPlaying
        pause()
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        if scrubResume { play() }
        scrubResume = false
    }

    func tearDown() {
        pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    // MARK: Filmstrip

    /// Poster frame for one tile of the strip (the middle of its span), cached for the session.
    func tileImage(span: Double, index: Int) async -> CGImage? {
        let key = "\(span)-\(index)"
        if let hit = tileCache[key] { return hit }
        guard !missingFile else { return nil }
        let image = await Self.frame(url: videoURL, at: min(duration, (Double(index) + 0.5) * span), tolerance: span / 2)
        if tileCache.count > 600 { tileCache.removeAll() }   // a few MB at most; zooming a lot starts over
        if let image { tileCache[key] = image }
        return image
    }

    nonisolated private static func frame(url: URL, at time: Double, tolerance: Double) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)
        let slack = CMTime(seconds: min(0.5, tolerance), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = slack
        generator.requestedTimeToleranceAfter = slack
        return try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }

    private func tick(_ t: Double) {
        guard isPlaying, t.isFinite else { return }   // AVFoundation reports NaN for unknown times
        time = t
        if t >= duration - 0.02 { isPlaying = false }
    }
}
