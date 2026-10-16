import Testing
import Foundation
@testable import RepasoCore

struct ExportTests {
    @Test func fileNameSanitises() {
        #expect(ClipExport.fileName(for: "Hammerlock exit") == "Hammerlock exit.mp4")
        #expect(ClipExport.fileName(for: "Turn 1/2: prep") == "Turn 1-2- prep.mp4")
        #expect(ClipExport.fileName(for: "   ") == "Clip.mp4")
        #expect(ClipExport.fileName(for: String(repeating: "a", count: 80)) == String(repeating: "a", count: 60) + ".mp4")
    }

    @Test func timeRangeClamps() {
        #expect(ClipExport.timeRange(start: -1, end: 5, duration: 10) == 0...5)
        #expect(ClipExport.timeRange(start: 8, end: 20, duration: 10) == 8...10)
        #expect(ClipExport.timeRange(start: 4, end: 4, duration: 10) == 4...4.1)
    }

    @Test func exportsOnlyTheRange() async throws {
        let dir = try TestVideo.tempDir()
        let source = try await TestVideo.make(seconds: 3, in: dir)
        let out = dir.appendingPathComponent("out.mp4")
        try await ClipExporter.export(source: source, range: 1...2, to: out) { _ in }
        let meta = try await VideoMetadata.load(out)
        #expect(abs(meta.duration - 1) < 0.15)
    }
}
