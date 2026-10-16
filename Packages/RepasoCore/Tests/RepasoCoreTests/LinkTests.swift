import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct LinkTests {
    let ctx: ModelContext
    let lib: LibraryService

    init() throws {
        ctx = try makeContext()
        lib = LibraryService(context: ctx)
    }

    func video(in folder: Folder?) throws -> Original {
        try lib.addOriginal(title: "Class", fileName: "c.mov", duration: 120, recordedAt: nil, to: folder)
    }

    @Test func linksSkipTheHomeAndDuplicates() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let teacher = try lib.createFolder(named: "Ataca", in: nil)
        let o = try video(in: turns)
        try lib.setLinks(o, to: [teacher, turns, teacher])
        #expect(o.linkedFolders.map(\.id) == [teacher.id])
        #expect(FolderContents.originals(in: teacher, sort: .manual).map(\.id) == [o.id])
        #expect(FolderContents.isLinked(o, in: teacher))
        #expect(!FolderContents.isLinked(o, in: turns))
        #expect(FolderContents.originals(in: turns, sort: .manual).count == 1)
    }

    @Test func clipLinksShowAsLooseClipsAndCountOnce() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let teacher = try lib.createFolder(named: "Ataca", in: nil)
        let clip = try lib.addClip(to: try video(in: turns), start: 1, end: 4)
        try lib.setLinks(clip, to: [teacher, turns])
        #expect(clip.linkedFolders.map(\.id) == [teacher.id])
        #expect(FolderContents.looseClips(in: teacher, sort: .manual, hideLearned: false).map(\.id) == [clip.id])
        #expect(FolderContents.clipCount(in: teacher) == 1)
        #expect(FolderContents.clipCount(in: turns) == 1)
        try lib.unlink(clip, from: teacher)
        #expect(clip.linkedFolders.isEmpty)
        #expect(FolderContents.looseClips(in: teacher, sort: .manual, hideLearned: false).isEmpty)
    }

    @Test func movingHomeIntoALinkedFolderDropsTheLink() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: nil)
        let o = try video(in: a)
        let clip = try lib.addClip(to: o, start: 1, end: 4)
        try lib.setLinks(o, to: [b])
        try lib.setLinks(clip, to: [b])
        try lib.moveOriginal(o, to: b)
        #expect(o.linkedFolders.isEmpty)
        #expect(clip.linkedFolders.isEmpty, "the clip lives with its video, now in B")
        try lib.setLinks(clip, to: [a])
        _ = try lib.dropClip(clip, on: a)
        #expect(clip.linkedFolders.isEmpty)
    }

    @Test func deletingAFolderThatOnlyLinksKeepsTheVideo() throws {
        let home = try lib.createFolder(named: "Home", in: nil)
        let collection = try lib.createFolder(named: "Collection", in: nil)
        let o = try video(in: home)
        try lib.setLinks(o, to: [collection])
        try lib.deleteFolder(collection, mode: .deleteContents)
        #expect(try ctx.fetchCount(FetchDescriptor<Original>()) == 1)
        #expect(o.linkedFolders.isEmpty)
    }

    @Test func moveContentsUpMovesLinksToTheParent() throws {
        let parent = try lib.createFolder(named: "Parent", in: nil)
        let child = try lib.createFolder(named: "Child", in: parent)
        let home = try lib.createFolder(named: "Home", in: nil)
        let o = try video(in: home)
        try lib.setLinks(o, to: [child])
        try lib.deleteFolder(child, mode: .moveContentsUp)
        #expect(o.linkedFolders.map(\.id) == [parent.id])
    }
}
