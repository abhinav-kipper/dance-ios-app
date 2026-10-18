import AVFoundation
import Observation
import RepasoCore

/// First frames of the current and neighbouring items, decoded ahead of time. Shown over the player while the
/// next item loads, so swiping between clips never flashes black.
@Observable @MainActor
final class StartFrames {
    private(set) var images: [String: CGImage] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    /// Changes when the clip is trimmed, so a new start decodes a new frame.
    static func key(_ clip: Clip) -> String { "\(clip.id)-\(clip.range.lowerBound)" }

    /// Keeps frames for `items` only, decoding any that are missing.
    func prefetch(_ items: [Clip], videos: VideoStore) {
        let keep = Set(items.map(Self.key))
        images = images.filter { keep.contains($0.key) }
        for (key, task) in tasks where !keep.contains(key) {
            task.cancel()
            tasks[key] = nil
        }
        for item in items {
            let key = Self.key(item)
            guard images[key] == nil, tasks[key] == nil, let recording = item.recording else { continue }
            let url = videos.url(for: recording.fileName)
            let time = item.range.lowerBound
            tasks[key] = Task { [weak self] in
                let image = await Self.decode(url: url, at: time)
                guard !Task.isCancelled, let self else { return }
                tasks[key] = nil
                if let image { images[key] = image }
            }
        }
    }

    /// The exact frame the player shows first (it seeks to the start with zero tolerance).
    nonisolated private static func decode(url: URL, at time: Double) async -> CGImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1080)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }
}
