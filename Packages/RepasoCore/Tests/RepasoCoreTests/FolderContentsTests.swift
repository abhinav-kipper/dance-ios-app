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

    @Test func originalsVersusLooseClips() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o1 = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: turns)
        let o2 = try lib.addOriginal(title: "Sat", fileName: "s.mov", duration: 60, recordedAt: nil, to: nil)
        _ = try lib.addClip(to: o1, start: 0, end: 1)
        let loose = try lib.addClip(to: o2, start: 0, end: 1)
        try lib.moveClip(loose, to: turns)
        #expect(FolderContents.originals(in: turns, sort: .manual).map(\.title) == ["Thu"])
        #expect(FolderContents.looseClips(in: turns, sort: .manual, hideLearned: false).map(\.id) == [loose.id])
        #expect(try FolderContents.unsortedOriginals(ctx).map(\.title) == ["Sat"])
        // The original still lists its moved clip.
        #expect(FolderContents.clips(of: o2, sort: .manual, hideLearned: false).count == 1)
    }

    @Test func sortsAndHidesLearned() throws {
        let o = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: nil)
        let a = try lib.addClip(to: o, start: 0, end: 1)
        let b = try lib.addClip(to: o, start: 2, end: 3)
        let c = try lib.addClip(to: o, start: 4, end: 5)
        try lib.updateInfo(a, name: "Zeta", note: "")
        try lib.updateInfo(b, name: "Alpha", note: "")
        a.addedAt = .init(timeIntervalSince1970: 1)
        b.addedAt = .init(timeIntervalSince1970: 3)
        c.addedAt = .init(timeIntervalSince1970: 2)
        try lib.markPlayed(c, at: .init(timeIntervalSince1970: 50))
        try lib.toggleLearned(b)
        #expect(FolderContents.clips(of: o, sort: .manual, hideLearned: false).map(\.name) == ["Zeta", "Alpha", "Clip 3"])
        #expect(FolderContents.clips(of: o, sort: .name, hideLearned: false).map(\.name) == ["Alpha", "Clip 3", "Zeta"])
        #expect(FolderContents.clips(of: o, sort: .dateAdded, hideLearned: false).map(\.name) == ["Alpha", "Clip 3", "Zeta"])
        #expect(FolderContents.clips(of: o, sort: .recentlyPlayed, hideLearned: false).first?.name == "Clip 3")
        #expect(FolderContents.clips(of: o, sort: .manual, hideLearned: true).map(\.name) == ["Zeta", "Clip 3"])
    }

    @Test func recursiveCountsAndTotals() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let sub = try lib.createFolder(named: "Sub", in: turns)
        let o = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: sub)
        let c1 = try lib.addClip(to: o, start: 0, end: 1)
        _ = try lib.addClip(to: o, start: 2, end: 3)
        try lib.moveClip(c1, to: turns)
        #expect(FolderContents.clipCount(in: turns) == 2)
        #expect(FolderContents.clipCount(in: sub) == 2)
        let totals = try FolderContents.totals(ctx)
        #expect(totals.clips == 2 && totals.folders == 2)
    }

    @Test func playQueueOrder() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: turns)
        let a = try lib.addClip(to: o, start: 0, end: 1)
        let other = try lib.addOriginal(title: "Sat", fileName: "s.mov", duration: 60, recordedAt: nil, to: nil)
        let l = try lib.addClip(to: other, start: 0, end: 1)
        try lib.moveClip(l, to: turns)
        let q = FolderContents.playQueue(
            originals: FolderContents.originals(in: turns, sort: .manual),
            loose: FolderContents.looseClips(in: turns, sort: .manual, hideLearned: false),
            sort: .manual, hideLearned: false)
        #expect(q.map(\.id) == [a.id, l.id])
    }

    @Test func mosaicPrefersClipsThenOriginals() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: turns)
        let c = try lib.addClip(to: o, start: 0, end: 10)
        let m = FolderContents.mosaic(for: turns)
        #expect(m.first?.id == c.id)
        #expect(m.count == 2)
        let empty = try lib.createFolder(named: "Empty", in: nil)
        #expect(FolderContents.mosaic(for: empty).isEmpty)
    }

    @Test func favorites() throws {
        let o = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: nil)
        let a = try lib.addClip(to: o, start: 0, end: 1)
        _ = try lib.addClip(to: o, start: 2, end: 3)
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
