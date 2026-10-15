import Testing
import Foundation
@testable import RepasoCore

struct StorageTests {
    @Test func adoptMovesFileWithExtension() throws {
        let root = try TestVideo.tempDir()
        let store = VideoStore(directory: root.appendingPathComponent("Videos"))
        let src = root.appendingPathComponent("IMG_0001.MOV")
        try Data([1, 2, 3]).write(to: src)
        let name = try store.adopt(fileAt: src)
        #expect(name.hasSuffix(".mov"))
        #expect(FileManager.default.fileExists(atPath: store.url(for: name).path))
        #expect(!FileManager.default.fileExists(atPath: src.path))
        #expect(store.fileSize(name) == 3)
    }

    @Test func sweepRemovesOnlyOrphans() throws {
        let root = try TestVideo.tempDir()
        let store = VideoStore(directory: root)
        for n in ["keep.mov", "orphan.mov"] { try Data([0]).write(to: root.appendingPathComponent(n)) }
        #expect(store.sweepOrphans(keeping: ["keep.mov"]) == ["orphan.mov"])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("keep.mov").path))
    }

    @Test func thumbnailGeneratedThenCachedOnDisk() async throws {
        let root = try TestVideo.tempDir()
        let videos = VideoStore(directory: root.appendingPathComponent("Videos"))
        let src = try await TestVideo.make(seconds: 2, in: root)
        let name = try videos.adopt(fileAt: src)
        let thumbsDir = root.appendingPathComponent("Thumbs")
        let thumbs = ThumbnailStore(directory: thumbsDir, videos: videos)
        let req = ThumbnailRequest(id: UUID(), fileName: name, time: 0.6)
        let image = await thumbs.image(for: req)
        #expect(image != nil)
        let file = thumbsDir.appendingPathComponent("\(req.id).jpg")
        #expect(FileManager.default.fileExists(atPath: file.path))
        await thumbs.remove(ids: [req.id])
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func missingVideoGivesNilThumbnail() async throws {
        let root = try TestVideo.tempDir()
        let thumbs = ThumbnailStore(directory: root, videos: VideoStore(directory: root))
        #expect(await thumbs.image(for: ThumbnailRequest(id: UUID(), fileName: "nope.mov", time: 1)) == nil)
    }
}
