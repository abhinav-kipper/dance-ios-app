import Foundation
import RepasoCore

/// Saves clips as their own short videos (exact frames), so the full video they came from can go.
@MainActor
enum OwnFileExporter {
    /// Exports each clip into the video store. Nothing in the library changes here: the caller hands the files to
    /// `LibraryService` in one save. On any failure the files made so far are removed and the error is rethrown.
    static func export(_ clips: [Clip], env: AppEnvironment,
                       progress: @escaping (Double) -> Void = { _ in }) async throws -> [LibraryService.OwnFile] {
        var made: [LibraryService.OwnFile] = []
        do {
            for (i, clip) in clips.enumerated() {
                progress(Double(i) / Double(max(clips.count, 1)))
                guard let recording = clip.recording else { continue }
                let source = env.videos.url(for: recording.fileName)
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
                let range = ClipExport.timeRange(start: clip.start, end: clip.end, duration: recording.duration)
                try await ClipExporter.export(source: source, range: range, to: temp) { _ in }
                let duration = (try? await VideoMetadata.load(temp).duration) ?? (range.upperBound - range.lowerBound)
                let fileName = try env.videos.adopt(fileAt: temp)
                made.append(.init(clipID: clip.id, fileName: fileName, duration: duration))
            }
            progress(1)
            return made
        } catch {
            discard(made, env: env)
            throw error
        }
    }

    /// Removes exported files that never made it into the library.
    static func discard(_ files: [LibraryService.OwnFile], env: AppEnvironment) {
        files.forEach { env.videos.remove(fileName: $0.fileName) }
    }
}
