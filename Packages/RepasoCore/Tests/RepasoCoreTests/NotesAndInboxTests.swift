import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct NotesAndInboxTests {
    let ctx: ModelContext
    let lib: LibraryService

    init() throws {
        ctx = try makeContext()
        lib = LibraryService(context: ctx)
    }

    @Test func placeKeepsHomeWhenTickedAndMovesOtherwise() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let teacher = try lib.createFolder(named: "Ataca", in: nil)
        let spins = try lib.createFolder(named: "Spins", in: nil)
        let clip = try lib.filedClip(in: turns)

        try lib.place(clip, in: [teacher, turns])
        #expect(clip.folder?.id == turns.id, "still lives in Turns")
        #expect(clip.linkedFolders.map(\.id) == [teacher.id])

        try lib.place(clip, in: [spins, teacher])
        #expect(clip.folder?.id == spins.id, "Turns unticked: it moves to the first ticked folder")
        #expect(clip.linkedFolders.map(\.id) == [teacher.id])

        try lib.place(clip, in: [])
        #expect(clip.folder?.id == spins.id, "a clip always lives somewhere; nothing ticked only clears the links")
        #expect(clip.linkedFolders.isEmpty)
    }

    @Test func notesTrimAndClear() throws {
        let clip = try lib.filedClip(in: try lib.createFolder(named: "Turns", in: nil))
        try lib.setNote(clip, "  Count 5: hand on her shoulder blade  ")
        #expect(clip.note == "Count 5: hand on her shoulder blade")
        try lib.setNote(clip, "   ")
        #expect(clip.note == nil)
    }
}
