import Testing
import Foundation
@testable import RepasoCore

struct ShareInboxTests {
    @Test func depositCopiesAndKeepsSource() throws {
        let root = try TestVideo.tempDir()
        let inbox = ShareInbox(directory: root.appendingPathComponent("Inbox"))
        let src = root.appendingPathComponent("IMG_0001.MOV")
        try Data([1, 2, 3]).write(to: src)
        let deposited = try inbox.deposit(fileAt: src)
        #expect(deposited.pathExtension == "mov")
        #expect(FileManager.default.fileExists(atPath: src.path))   // Photos owns its temp file
        #expect(try Data(contentsOf: deposited) == Data([1, 2, 3]))
    }

    @Test func drainMovesFilesOutInShareOrder() throws {
        let root = try TestVideo.tempDir()
        let inbox = ShareInbox(directory: root.appendingPathComponent("Inbox"))
        let dest = root.appendingPathComponent("Out")
        for byte: UInt8 in [1, 2, 3] {
            let src = root.appendingPathComponent("v\(byte).mp4")
            try Data([byte]).write(to: src)
            try inbox.deposit(fileAt: src)
        }
        let drained = inbox.drain(into: dest)
        #expect(try drained.map { try Data(contentsOf: $0) } == [Data([1]), Data([2]), Data([3])])
        #expect(drained.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL == dest.standardizedFileURL })
        #expect(inbox.drain(into: dest).isEmpty)
    }

    @Test func drainSkipsHalfWrittenFiles() throws {
        let root = try TestVideo.tempDir()
        let inbox = ShareInbox(directory: root.appendingPathComponent("Inbox"))
        try Data([9]).write(to: inbox.directory.appendingPathComponent(".partial-abc.mov"))
        #expect(inbox.drain(into: root.appendingPathComponent("Out")).isEmpty)
        #expect(FileManager.default.fileExists(atPath: inbox.directory.appendingPathComponent(".partial-abc.mov").path))
    }

    @Test func emptyExtensionFallsBackToMov() throws {
        let root = try TestVideo.tempDir()
        let inbox = ShareInbox(directory: root.appendingPathComponent("Inbox"))
        let src = root.appendingPathComponent("noext")
        try Data([0]).write(to: src)
        #expect(try inbox.deposit(fileAt: src).pathExtension == "mov")
    }
}
