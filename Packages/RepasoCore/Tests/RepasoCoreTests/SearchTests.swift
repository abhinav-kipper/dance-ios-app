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
    let hammerlock: Clip
    let basic: Clip

    init() throws {
        ctx = try makeContext()
        lib = LibraryService(context: ctx)
        turns = try lib.createFolder(named: "Turns", in: nil)
        ataca = try lib.createFolder(named: "Ataca & Alemana", in: nil)
        let workshop = try lib.filedRecording(duration: 200)
        hammerlock = try lib.filedClip("Hammerlock exit", in: turns, on: workshop, start: 1, end: 5,
                                       instructors: ["Ataca & Alemana"])
        try lib.setNote(hammerlock, "Lift on count 3 · Bachatá Festival")
        basic = try lib.filedClip("Basic step", in: turns, on: workshop, start: 10, end: 14, instructors: ["Ataca & Alemana"])
        try lib.setLinks(basic, to: [ataca])
    }

    func search(_ q: String) throws -> LibrarySearch.Results {
        LibrarySearch.results(for: q,
                              clips: try ctx.fetch(FetchDescriptor<Clip>()),
                              folders: try ctx.fetch(FetchDescriptor<Folder>()))
    }

    @Test func emptyQueryFindsNothing() throws {
        #expect(try search("   ").isEmpty)
    }

    @Test func matchesNamesCaseAndAccentInsensitive() throws {
        let r = try search("HAMMER")
        #expect(r.clips.map(\.id) == [hammerlock.id])
        #expect(try search("bachata festival").clips.map(\.id) == [hammerlock.id], "accent-insensitive")
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

    @Test func findsByNoteAndFolder() throws {
        #expect(try search("count 3").clips.map(\.id) == [hammerlock.id])
        #expect(try search("ataca basic").clips.map(\.id) == [basic.id])
        #expect(try search("turns").folders.map(\.id) == [turns.id])
    }

    @Test func shortWordsOnlyMatchWordStarts() throws {
        #expect(try search("ex").clips.map(\.id) == [hammerlock.id], "prefix of 'exit'")
        #expect(try search("it").clips.isEmpty, "two letters inside a word don't count")
    }
}
