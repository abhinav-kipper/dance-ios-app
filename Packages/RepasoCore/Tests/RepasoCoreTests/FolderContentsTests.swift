import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct FolderContentsTests {
    let ctx: ModelContext
    let lib: LibraryService

    init() throws {
        ctx = try makeContext()
        lib = LibraryService(context: ctx)
    }

    @Test func sortsAndHidesLearned() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let r = try lib.filedRecording()
        let a = try lib.filedClip("Zeta", in: turns, on: r)
        let b = try lib.filedClip("Alpha", in: turns, on: r)
        let c = try lib.filedClip("Clip 3", in: turns, on: r)
        a.addedAt = .init(timeIntervalSince1970: 1)
        b.addedAt = .init(timeIntervalSince1970: 3)
        c.addedAt = .init(timeIntervalSince1970: 2)
        try lib.markPlayed(c, at: .init(timeIntervalSince1970: 50))
        try lib.toggleLearned(b)
        func names(_ sort: ClipSort, hide: Bool = false) -> [String] {
            FolderContents.folderClips(in: turns, sort: sort, hideLearned: hide).map(\.name)
        }
        #expect(names(.manual) == ["Zeta", "Alpha", "Clip 3"])
        #expect(names(.name) == ["Alpha", "Clip 3", "Zeta"])
        #expect(names(.dateAdded) == ["Alpha", "Clip 3", "Zeta"])
        #expect(names(.recentlyPlayed).first == "Clip 3")
        #expect(names(.manual, hide: true) == ["Zeta", "Clip 3"])
    }

    @Test func manualOrderGroupsByVideoNewestFirst() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let old = try lib.filedRecording(recordedAt: .init(timeIntervalSince1970: 10))
        let new = try lib.filedRecording(recordedAt: .init(timeIntervalSince1970: 20))
        let o1 = try lib.filedClip("Old 1", in: turns, on: old)
        let n1 = try lib.filedClip("New 1", in: turns, on: new)
        let o2 = try lib.filedClip("Old 2", in: turns, on: old)
        #expect(FolderContents.folderClips(in: turns, sort: .manual, hideLearned: false).map(\.id) == [n1.id, o1.id, o2.id])
    }

    @Test func recursiveCountsAndTotals() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let sub = try lib.createFolder(named: "Sub", in: turns)
        _ = try lib.filedClip(in: turns)
        _ = try lib.filedClip(in: sub)
        #expect(FolderContents.clipCount(in: turns) == 2, "a folder counts its subfolders' clips too")
        #expect(FolderContents.clipCount(in: sub) == 1)
        let totals = try FolderContents.totals(ctx)
        #expect(totals.clips == 2 && totals.folders == 2)
    }

    @Test func mosaicRecursesIntoSubfolders() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let sub = try lib.createFolder(named: "Sub", in: turns)
        let c = try lib.filedClip(in: sub)
        #expect(FolderContents.mosaic(for: turns).map(\.id) == [c.id])
        let empty = try lib.createFolder(named: "Empty", in: nil)
        #expect(FolderContents.mosaic(for: empty).isEmpty)
    }

    @Test func favorites() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let a = try lib.filedClip("A", in: turns)
        _ = try lib.filedClip("B", in: turns)
        try lib.toggleFavorite(a)
        #expect(try FolderContents.favorites(ctx, sort: .manual).map(\.id) == [a.id])
    }

    @Test func rootFoldersInOrder() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: nil)
        _ = try lib.createFolder(named: "Child", in: a)
        #expect(try FolderContents.rootFolders(ctx).map(\.id) == [b.id, a.id])
    }
}

@MainActor
struct ClipOrderTests {
    let ctx: ModelContext
    let lib: LibraryService

    init() throws {
        ctx = try makeContext()
        lib = LibraryService(context: ctx)
    }

    func ids(_ folder: Folder) -> [UUID] {
        FolderContents.folderClips(in: folder, sort: .manual, hideLearned: false).map(\.id)
    }

    @Test func dragOrderIsKept() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let r = try lib.filedRecording()
        let a = try lib.filedClip("A", in: turns, on: r)
        let b = try lib.filedClip("B", in: turns, on: r)
        let c = try lib.filedClip("C", in: turns, on: r)
        try lib.setClipOrder([c, a, b], in: turns)
        #expect(ids(turns) == [c.id, a.id, b.id])
    }

    @Test func newClipsArriveOnTopOfAnArrangedFolder() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let a = try lib.filedClip("A", in: turns)
        let b = try lib.filedClip("B", in: turns)
        try lib.setClipOrder([b, a], in: turns)
        let new = try lib.filedClip("New", in: turns)
        #expect(ids(turns) == [new.id, b.id, a.id])
    }

    @Test func movingAClipForgetsItsPlaceInTheOldFolder() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let spins = try lib.createFolder(named: "Spins", in: nil)
        let a = try lib.filedClip("A", in: spins)
        let b = try lib.filedClip("B", in: spins)
        let moved = try lib.filedClip("Moved", in: turns)
        try lib.setClipOrder([a, b], in: spins)
        try lib.setClipOrder([moved], in: turns)
        _ = try lib.dropClip(moved, on: spins)
        #expect(ids(spins) == [moved.id, a.id, b.id], "it lands on top, not at its old index")
    }

    @Test func orderOnlyForClipsLivingThere() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let spins = try lib.createFolder(named: "Spins", in: nil)
        let a = try lib.filedClip("A", in: turns)
        let elsewhere = try lib.filedClip("B", in: spins)
        #expect(throws: LibraryError.invalidMoveTarget) { try lib.setClipOrder([a, elsewhere], in: turns) }
    }
}
