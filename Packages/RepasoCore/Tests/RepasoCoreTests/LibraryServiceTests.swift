import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct LibraryServiceTests {
    /// Per-test instance: Swift Testing runs tests in parallel.
    final class Removed { var files: [String] = [] }

    let ctx: ModelContext
    let lib: LibraryService
    let removedBox = Removed()
    var removed: [String] { removedBox.files }

    init() throws {
        ctx = try makeContext()
        let box = removedBox
        lib = LibraryService(context: ctx) { files, _ in box.files += files }
    }

    func original(_ title: String = "Class", in folder: Folder? = nil, duration: Double = 120) throws -> Original {
        try lib.addOriginal(title: title, fileName: "\(title).mov", duration: duration, recordedAt: nil, to: folder)
    }

    // MARK: Folders

    @Test func createFolderInsertsAtTopWithDefaultName() throws {
        let a = try lib.createFolder(named: "Turns", in: nil)
        let b = try lib.createFolder(named: "   ", in: nil)
        #expect(b.name == "New folder")
        #expect(b.sortIndex == 0)
        #expect(a.sortIndex == 1)
    }

    @Test func rejectsMoveIntoDescendant() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: a)
        #expect(throws: LibraryError.invalidMoveTarget) { try lib.moveFolder(a, to: b) }
        #expect(throws: LibraryError.invalidMoveTarget) { try lib.moveFolder(a, to: a) }
    }

    @Test func reorderSwapsWithNeighbour() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: nil)
        try lib.reorderFolder(b, by: 1)
        #expect(a.sortIndex == 0 && b.sortIndex == 1)
        try lib.reorderFolder(b, by: 1)
        #expect(b.sortIndex == 1)
    }

    @Test func deleteContentsCascadesClipsFiledElsewhere() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let sub = try lib.createFolder(named: "Sub", in: turns)
        let other = try lib.createFolder(named: "Other", in: nil)
        let o = try original("Thursday", in: sub)
        let c = try lib.addClip(to: o, start: 1, end: 4)
        try lib.moveClip(c, to: other)
        try lib.deleteFolder(turns, mode: .deleteContents)
        #expect(try ctx.fetchCount(FetchDescriptor<Folder>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<Original>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<Clip>()) == 0)
        #expect(removed == ["Thursday.mov"])
    }

    @Test func deleteContentsKeepsLooseClipsFromOutside() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let outside = try original("Saturday")
        let loose = try lib.addClip(to: outside, start: 0, end: 2)
        try lib.moveClip(loose, to: turns)
        try lib.deleteFolder(turns, mode: .deleteContents)
        // The loose bookmark is deleted, its original survives.
        #expect(try ctx.fetchCount(FetchDescriptor<Clip>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<Original>()) == 1)
        #expect(removed.isEmpty)
    }

    @Test func moveContentsUpToRoot() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let sub = try lib.createFolder(named: "Sub", in: turns)
        let o = try original("Thursday", in: turns)
        let elsewhere = try original("Saturday", in: nil)
        let loose = try lib.addClip(to: elsewhere, start: 0, end: 2)
        try lib.moveClip(loose, to: turns)
        try lib.deleteFolder(turns, mode: .moveContentsUp)
        #expect(sub.parent == nil)
        #expect(o.folder == nil)
        #expect(loose.folder == nil)
        #expect(removed.isEmpty)
    }

    @Test func moveContentsUpToParent() throws {
        let home = try lib.createFolder(named: "Home2", in: nil)
        let turns = try lib.createFolder(named: "Turns", in: home)
        let o = try original("Thursday", in: turns)
        try lib.deleteFolder(turns, mode: .moveContentsUp)
        #expect(o.folder?.id == home.id)
    }

    // MARK: Originals

    @Test func deleteOriginalRemovesClipsAndFile() throws {
        let other = try lib.createFolder(named: "Other", in: nil)
        let o = try original()
        let c = try lib.addClip(to: o, start: 0, end: 1)
        try lib.moveClip(c, to: other)
        try lib.deleteOriginal(o)
        #expect(try ctx.fetchCount(FetchDescriptor<Clip>()) == 0)
        #expect(other.looseClips.isEmpty)
        #expect(removed == ["Class.mov"])
    }

    @Test func normalisesClipWhenOriginalJoinsItsFolder() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o = try original()
        let c = try lib.addClip(to: o, start: 0, end: 1)
        try lib.moveClip(c, to: turns)
        #expect(c.isFiledElsewhere)
        try lib.moveOriginal(o, to: turns)
        #expect(c.folder == nil)
        #expect(!c.isFiledElsewhere)
    }

    // MARK: Clips

    @Test func clipNamesAreMonotonic() throws {
        let o = try original()
        let c1 = try lib.addClip(to: o, start: 0, end: 1)
        let c2 = try lib.addClip(to: o, start: 2, end: 3)
        try lib.deleteClip(c2)
        let c3 = try lib.addClip(to: o, start: 4, end: 5)
        #expect([c1.name, c3.name] == ["Clip 1", "Clip 3"])
        #expect(c3.sortIndex > c1.sortIndex)
    }

    @Test func addClipNormalisesRange() throws {
        let o = try original(duration: 10)
        let c = try lib.addClip(to: o, start: 9.9, end: 9.8)
        #expect(c.start == 9.5 && c.end == 10)
    }

    @Test func moveClipBackToItsVideo() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o = try original()
        let c = try lib.addClip(to: o, start: 0, end: 1)
        try lib.moveClip(c, to: turns)
        try lib.moveClip(c, to: nil)
        #expect(c.folder == nil)
        try lib.moveClip(c, to: turns)
        try lib.moveOriginal(o, to: nil)
        try lib.moveClip(c, to: nil)
        #expect(c.folder == nil)
    }

    @Test func infoTrimsAndCapsNote() throws {
        let c = try lib.addClip(to: try original(), start: 0, end: 1)
        try lib.updateInfo(c, name: "  ", note: String(repeating: "a", count: 200))
        #expect(c.name == "Clip 1")
        #expect(c.note?.count == 140)
        try lib.updateInfo(c, name: "Hammerlock", note: "   ")
        #expect(c.name == "Hammerlock")
        #expect(c.note == nil)
    }

    @Test func togglesAndPlayed() throws {
        let c = try lib.addClip(to: try original(), start: 0, end: 1)
        try lib.toggleFavorite(c)
        try lib.toggleLearned(c)
        #expect(c.isFavorite && c.isLearned)
        let now = Date(timeIntervalSince1970: 100)
        try lib.markPlayed(c, at: now)
        #expect(c.lastPlayedAt == now)
    }

    @Test func normalizedClampsToTinyDuration() {
        #expect(ClipRange.normalized(start: 0, end: 0.1, duration: 0.3) == 0...0.3)
        #expect(ClipRange.normalized(start: 5, end: 2, duration: 10) == 2...5)
        #expect(ClipRange.normalized(start: -1, end: 0.2, duration: 10) == 0...0.5)
    }
}
