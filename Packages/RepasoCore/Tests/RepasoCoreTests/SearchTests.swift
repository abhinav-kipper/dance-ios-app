import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct SearchTests {
    let ctx: ModelContext
    let lib: LibraryService
    let turns: Folder
    let ataca: Folder
    let workshop: Original
    let hammerlock: Clip
    let basic: Clip

    init() throws {
        ctx = try makeContext()
        lib = LibraryService(context: ctx)
        turns = try lib.createFolder(named: "Turns", in: nil)
        ataca = try lib.createFolder(named: "Ataca & Alemana", in: nil)
        workshop = try lib.addOriginal(title: "Berlin workshop", fileName: "w.mov", duration: 200, recordedAt: nil, to: turns,
                                       instructors: ["Ataca & Alemana"], event: "Bachatá Festival")
        hammerlock = try lib.addClip(to: workshop, start: 1, end: 5)
        try lib.updateInfo(hammerlock, name: "Hammerlock exit", note: "Lift on count 3")
        basic = try lib.addClip(to: workshop, start: 10, end: 14)
        try lib.updateInfo(basic, name: "Basic step", note: "")
        try lib.setLinks(basic, to: [ataca])
    }

    func search(_ q: String) throws -> LibrarySearch.Results {
        LibrarySearch.results(for: q,
                              clips: try ctx.fetch(FetchDescriptor<Clip>()),
                              videos: try ctx.fetch(FetchDescriptor<Original>()),
                              folders: try ctx.fetch(FetchDescriptor<Folder>()))
    }

    @Test func emptyQueryFindsNothing() throws {
        #expect(try search("   ").isEmpty)
    }

    @Test func matchesNamesCaseAndAccentInsensitive() throws {
        let r = try search("HAMMER")
        #expect(r.clips.map(\.id) == [hammerlock.id])
        #expect(try search("bachata festival").videos.map(\.id) == [workshop.id], "accent-insensitive")
    }

    @Test func everyWordMustMatchSomewhere() throws {
        #expect(try search("ataca basic").clips.map(\.id) == [basic.id], "instructor + clip name")
        #expect(try search("ataca zouk").clips.isEmpty)
    }

    @Test func nameMatchesRankFirst() throws {
        // "ataca" is in both clips' instructors, but only the folder is *named* Ataca.
        let r = try search("ataca")
        #expect(r.folders.map(\.id) == [ataca.id])
        #expect(Set(r.clips.map(\.id)) == [hammerlock.id, basic.id])
        #expect(try search("step").clips.first?.id == basic.id)
    }

    @Test func findsByNoteEventAndLinkedFolder() throws {
        #expect(try search("count 3").clips.map(\.id) == [hammerlock.id])
        #expect(try search("berlin").videos.map(\.id) == [workshop.id])
        #expect(try search("turns").folders.map(\.id) == [turns.id])
    }

    @Test func shortWordsOnlyMatchWordStarts() throws {
        #expect(try search("ex").clips.map(\.id) == [hammerlock.id], "prefix of 'exit'")
        #expect(try search("it").clips.isEmpty, "two letters inside a word don't count")
    }
}
