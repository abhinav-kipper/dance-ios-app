import Testing
import SwiftData
@testable import RepasoCore

@MainActor
struct ModelTests {
    @Test func cascadeDeletesClips() throws {
        let ctx = try makeContext()
        let o = Original(title: "Class", fileName: "a.mov", duration: 60, recordedAt: nil, folder: nil)
        ctx.insert(o)
        let c = Clip(name: "Clip 1", start: 1, end: 3, sortIndex: 0, original: o)
        ctx.insert(c)
        try ctx.save()
        ctx.delete(o)
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<Clip>()) == 0)
    }

    @Test func descendantCheck() throws {
        let ctx = try makeContext()
        let a = Folder(name: "A", sortIndex: 0)
        let b = Folder(name: "B", sortIndex: 0, parent: a)
        let c = Folder(name: "C", sortIndex: 0, parent: b)
        [a, b, c].forEach(ctx.insert)
        #expect(c.isDescendant(of: a))
        #expect(!a.isDescendant(of: c))
        #expect(c.ancestors.map(\.name) == ["A", "B"])
    }

    @Test func thumbnailTimes() throws {
        let o = Original(title: "x", fileName: "x.mov", duration: 100, recordedAt: nil, folder: nil)
        #expect(o.thumbnailRequest.time == 30)
        let c = Clip(name: "c", start: 10, end: 20, sortIndex: 0, original: o)
        #expect(c.thumbnailRequest?.time == 13)
        #expect(c.thumbnailRequest?.fileName == "x.mov")
    }
}
