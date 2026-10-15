import Testing
@testable import RepasoCore

struct VideoMetadataTests {
    @Test func readsDuration() async throws {
        let url = try await TestVideo.make(seconds: 2, in: try TestVideo.tempDir())
        let meta = try await VideoMetadata.load(url)
        #expect(abs(meta.duration - 2) < 0.2)
    }
}
