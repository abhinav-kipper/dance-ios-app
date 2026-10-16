import AVFoundation

/// Writes just a clip's range of its original to an .mp4 for sharing.
public enum ClipExporter {
    public enum ExportError: Error { case unavailable }

    public static func export(source: URL, range: ClosedRange<Double>, to destination: URL,
                              progress: @escaping @Sendable (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        // HighestQuality re-encodes, so the clip starts on the exact frame (passthrough snaps to keyframes).
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.unavailable
        }
        session.timeRange = CMTimeRange(start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                                        end: CMTime(seconds: range.upperBound, preferredTimescale: 600))
        // The session isn't Sendable, but observing its states while it exports is the API's intended use.
        nonisolated(unsafe) let observed = session
        let watcher = Task {
            for await state in observed.states(updateInterval: 0.1) {
                if case .exporting(let p) = state { progress(p.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        do {
            try await session.export(to: destination, as: .mp4)
            progress(1)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
