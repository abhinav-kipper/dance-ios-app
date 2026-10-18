import Foundation
import SwiftData
import RepasoCore

/// "Keep only the clips": saves each clip of a video as its own short video, so the full video can be deleted.
@MainActor
enum ClipKeeper {
    /// Exports every clip of `original` (exact frames) and points the clip at its own file. The full video stays until
    /// the caller deletes it, so a failure part-way leaves everything playable. Reports clips finished so far.
    static func saveClipsAsOwnVideos(of original: Original, env: AppEnvironment, context: ModelContext,
                                     progress: (Int, Int) -> Void) async throws {
        let clips = original.clips.sorted { $0.start < $1.start }
        let source = env.videos.url(for: original.fileName)
        let lib = env.library(context)
        for (i, clip) in clips.enumerated() {
            progress(i, clips.count)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
            let range = ClipExport.timeRange(start: clip.start, end: clip.end, duration: original.duration)
            try await ClipExporter.export(source: source, range: range, to: temp) { _ in }
            let duration = (try? await VideoMetadata.load(temp).duration) ?? (range.upperBound - range.lowerBound)
            let fileName = try env.videos.adopt(fileAt: temp)
            try lib.detach(clip, intoFile: fileName, duration: duration)
        }
        progress(clips.count, clips.count)
    }

    /// "1.2 GB": what deleting the full video frees, roughly (the clips' own files are small next to it).
    static func sizeText(of original: Original, env: AppEnvironment) -> String? {
        env.videos.fileSize(original.fileName).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }
}
