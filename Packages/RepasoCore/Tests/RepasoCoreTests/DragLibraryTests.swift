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

    @Test func dropClipFilesItAndUndoPutsItBack() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let hammer = try lib.createFolder(named: "Hammerlock", in: turns)
        let clip = try lib.filedClip(in: turns)
        let receipt = try #require(try lib.dropClip(clip, on: hammer))
        #expect(clip.folder?.id == hammer.id)
        #expect(receipt.previousFolder?.id == turns.id)
        try lib.undo(receipt)
        #expect(clip.folder?.id == turns.id)
    }

    @Test func dropClipIsNoOpOnItsOwnFolder() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let clip = try lib.filedClip(in: turns)
        #expect(try lib.dropClip(clip, on: turns) == nil)
        #expect(clip.folder?.id == turns.id)
    }

    @Test func undoAfterPreviousFolderDeletedLeavesItWhereItIs() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: nil)
        let clip = try lib.filedClip(in: a)
        let receipt = try #require(try lib.dropClip(clip, on: b))
        try lib.deleteFolder(a, mode: .deleteContents)
        try lib.undo(receipt)
        #expect(clip.folder?.id == b.id)
    }
}
