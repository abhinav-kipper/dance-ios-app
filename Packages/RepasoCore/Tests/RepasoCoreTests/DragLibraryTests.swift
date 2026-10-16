import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct DragLibraryTests {
    let ctx: ModelContext
    let lib: LibraryService

    init() throws {
        ctx = try makeContext()
        lib = LibraryService(context: ctx)
    }

    func original(in folder: Folder?) throws -> Original {
        try lib.addOriginal(title: "Class", fileName: "c.mov", duration: 120, recordedAt: nil, to: folder)
    }

    @Test func setFolderOrderPersistsPositions() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: nil)
        let c = try lib.createFolder(named: "C", in: nil)
        try lib.setFolderOrder([a, c, b])
        #expect([a.sortIndex, c.sortIndex, b.sortIndex] == [Int]([0, 1, 2]))
    }

    @Test func setFolderOrderRejectsMixedParents() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: a)
        #expect(throws: LibraryError.invalidMoveTarget) { try lib.setFolderOrder([a, b]) }
    }

    @Test func dropClipFilesItAndUndoRestoresWithItsVideo() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let hammer = try lib.createFolder(named: "Hammerlock", in: turns)
        let clip = try lib.addClip(to: try original(in: turns), start: 1, end: 4)
        let receipt = try #require(try lib.dropClip(clip, on: hammer))
        #expect(clip.folder?.id == hammer.id)
        #expect(receipt.previousFolder == nil)
        try lib.undo(receipt)
        #expect(clip.folder == nil)
    }

    @Test func undoRestoresAPreviousFolder() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: nil)
        let clip = try lib.addClip(to: try original(in: nil), start: 1, end: 4)
        try lib.moveClip(clip, to: a)
        let receipt = try #require(try lib.dropClip(clip, on: b))
        try lib.undo(receipt)
        #expect(clip.folder?.id == a.id)
    }

    @Test func dropClipIsNoOpOnItsOwnFolder() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let clip = try lib.addClip(to: try original(in: turns), start: 1, end: 4)
        #expect(try lib.dropClip(clip, on: turns) == nil)
        #expect(clip.folder == nil)
    }

    @Test func dropOnOriginalsFolderBringsClipBackWithItsVideo() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let other = try lib.createFolder(named: "Other", in: nil)
        let clip = try lib.addClip(to: try original(in: turns), start: 1, end: 4)
        try lib.moveClip(clip, to: other)
        _ = try lib.dropClip(clip, on: turns)
        #expect(clip.folder == nil)
        #expect(clip.effectiveFolder?.id == turns.id)
    }

    @Test func undoAfterPreviousFolderDeletedFilesWithVideo() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: nil)
        let clip = try lib.addClip(to: try original(in: nil), start: 1, end: 4)
        try lib.moveClip(clip, to: a)
        let receipt = try #require(try lib.dropClip(clip, on: b))
        try lib.deleteFolder(a, mode: .deleteContents)
        try lib.undo(receipt)
        #expect(clip.folder == nil)
    }

    @Test func setTagsNormalises() throws {
        let o = try original(in: nil)
        try lib.setTags([o], instructors: [" Marco ", "marco", "", "Sara"], event: "  ")
        #expect(o.instructors == ["Marco", "Sara"])
        #expect(o.event == nil)
        try lib.setTags([o], instructors: [], event: " Berlin 2026 ")
        #expect(o.event == "Berlin 2026")
    }

    @Test func addOriginalStoresTags() throws {
        let o = try lib.addOriginal(title: "T", fileName: "t.mov", duration: 10, recordedAt: nil, to: nil,
                                    instructors: ["Ataca & Alemana"], event: "Berlin 2026")
        #expect(o.instructors == ["Ataca & Alemana"])
        #expect(o.event == "Berlin 2026")
    }
}
