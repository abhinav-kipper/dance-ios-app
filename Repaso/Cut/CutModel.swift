import AVFoundation
import Observation
import RepasoCore

/// Playback, mark state and filmstrip frames for Cut mode.
@Observable @MainActor
final class CutModel {
    static let frameCount = 10

    let player = AVPlayer()
    let duration: Double
    private(set) var time: Double = 0
    private(set) var isPlaying = false
    private(set) var missingFile = false
    var session: CutSession
    var selectedID: UUID?
    /// Live range while a trim handle is dragged (saved on release).
    var draftRange: ClosedRange<Double>?
    /// Window start held still while scrubbing or trimming.
    var frozenWindowStart: Double?
    private(set) var frames: [CGImage?] = Array(repeating: nil, count: frameCount)

    private let videoURL: URL
    private var frameCache: [Int: [CGImage?]] = [:]
    private var timeObserver: Any?
    private var scrubResume = false

    init(original: Original, videos: VideoStore) {
        duration = original.duration
        session = CutSession(duration: original.duration)
        videoURL = videos.url(for: original.fileName)
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
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] t in
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

    func jump(_ delta: Double) { seek(time + delta) }

    /// Precise seeks when settled; looser while dragging so the frame keeps up with the finger.
    func seek(_ t: Double, precise: Bool = true) {
        guard t.isFinite else { return }
        let clamped = min(max(0, t), duration)
        time = clamped
        let tolerance = precise ? CMTime.zero : CMTime(seconds: 0.1, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func beginScrub() {
        scrubResume = isPlaying
        pause()
    }

    func endScrub() {
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

    func windowStart(selected: Clip?) -> Double {
        if let frozenWindowStart { return frozenWindowStart }
        let center = selected.map { ($0.start + $0.end) / 2 } ?? time
        return CutSession.windowStart(center: center, duration: duration)
    }

    func loadFrames(windowStart: Double) async {
        let key = Int((windowStart * 10).rounded())
        if let cached = frameCache[key] {
            frames = cached
            return
        }
        guard !missingFile else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let length = CutSession.windowLength(for: duration)
        var loaded: [CGImage?] = []
        for i in 0..<Self.frameCount {
            let t = windowStart + length * (Double(i) + 0.5) / Double(Self.frameCount)
            let image = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
            loaded.append(image)
            if Task.isCancelled { return }
        }
        frameCache[key] = loaded
        frames = loaded
    }

    private func tick(_ t: Double) {
        guard isPlaying, t.isFinite else { return }   // AVFoundation reports NaN for unknown times
        time = t
        if t >= duration - 0.02 { isPlaying = false }
    }
}
