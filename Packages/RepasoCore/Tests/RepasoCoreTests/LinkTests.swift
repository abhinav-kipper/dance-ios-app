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

    @Test func linksSkipTheHomeAndDuplicates() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let teacher = try lib.createFolder(named: "Ataca", in: nil)
        let clip = try lib.filedClip(in: turns)
        try lib.setLinks(clip, to: [teacher, turns, teacher])
        #expect(clip.linkedFolders.map(\.id) == [teacher.id])
        #expect(FolderContents.isLinked(clip, in: teacher))
        #expect(!FolderContents.isLinked(clip, in: turns))
    }

    @Test func linkedClipsShowAfterHomeClipsAndCountOnce() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let teacher = try lib.createFolder(named: "Ataca", in: nil)
        let linked = try lib.filedClip("Linked", in: turns)
        let home = try lib.filedClip("Home", in: teacher)
        try lib.setLinks(linked, to: [teacher])
        #expect(FolderContents.folderClips(in: teacher, sort: .manual, hideLearned: false).map(\.id) == [home.id, linked.id])
        #expect(FolderContents.clipCount(in: teacher) == 2)
        #expect(FolderContents.clipCount(in: turns) == 1)
        try lib.unlink(linked, from: teacher)
        #expect(linked.linkedFolders.isEmpty)
        #expect(FolderContents.folderClips(in: teacher, sort: .manual, hideLearned: false).map(\.id) == [home.id])
    }

    @Test func movingHomeIntoALinkedFolderDropsTheLink() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: nil)
        let clip = try lib.filedClip(in: a)
        try lib.setLinks(clip, to: [b])
        _ = try lib.dropClip(clip, on: b)
        #expect(clip.folder?.id == b.id)
        #expect(clip.linkedFolders.isEmpty)
    }

    @Test func deletingAFolderThatOnlyLinksKeepsTheClip() throws {
        let home = try lib.createFolder(named: "Home", in: nil)
        let collection = try lib.createFolder(named: "Collection", in: nil)
        let clip = try lib.filedClip(in: home)
        try lib.setLinks(clip, to: [collection])
        try lib.deleteFolder(collection, mode: .deleteContents)
        #expect(try ctx.fetchCount(FetchDescriptor<Clip>()) == 1)
        #expect(clip.linkedFolders.isEmpty)
    }

    @Test func moveContentsUpMovesLinksToTheParent() throws {
        let parent = try lib.createFolder(named: "Parent", in: nil)
        let child = try lib.createFolder(named: "Child", in: parent)
        let home = try lib.createFolder(named: "Home", in: nil)
        let clip = try lib.filedClip(in: home)
        try lib.setLinks(clip, to: [child])
        try lib.deleteFolder(child, mode: .moveContentsUp)
        #expect(clip.linkedFolders.map(\.id) == [parent.id])
    }
}
