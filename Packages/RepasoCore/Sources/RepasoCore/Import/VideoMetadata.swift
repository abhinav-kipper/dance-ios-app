import AVFoundation

public enum VideoMetadata {
    public static func load(_ url: URL) async throws -> (duration: Double, recordedAt: Date?) {
        let asset = AVURLAsset(url: url)
        let (duration, creation) = try await asset.load(.duration, .creationDate)
        let recordedAt = try? await creation?.load(.dateValue)
        return (duration.seconds.isFinite ? duration.seconds : 0, recordedAt ?? nil)
    }
}
