import Testing
import SwiftData
@testable import RepasoCore

@MainActor
struct ModelTests {
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
}
