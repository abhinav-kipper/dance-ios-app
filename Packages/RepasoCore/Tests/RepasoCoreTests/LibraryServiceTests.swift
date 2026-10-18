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

    @Test func deleteContentsDeletesClipsLivingThere() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let sub = try lib.createFolder(named: "Sub", in: turns)
        let other = try lib.createFolder(named: "Other", in: nil)
        let shared = try lib.filedRecording("Thursday.mov")
        let inSub = try lib.filedClip("In sub", in: sub, on: shared)
        let elsewhere = try lib.filedClip("Elsewhere", in: other, on: shared)
        _ = try lib.filedClip("Alone", in: turns, on: try lib.filedRecording("Saturday.mov"))
        try lib.deleteFolder(turns, mode: .deleteContents)
        #expect(try ctx.fetchCount(FetchDescriptor<Folder>()) == 1)
        #expect(try ctx.fetch(FetchDescriptor<Clip>()).map(\.id) == [elsewhere.id])
        #expect(inSub.isDeleted || inSub.modelContext == nil)
        #expect(removed == ["Saturday.mov"], "Thursday.mov is still used by the clip in Other")
    }

    @Test func deleteContentsKeepsClipsOnlyLinkedThere() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let home = try lib.createFolder(named: "Home", in: nil)
        let clip = try lib.filedClip(in: home)
        try lib.setLinks(clip, to: [turns])
        try lib.deleteFolder(turns, mode: .deleteContents)
        #expect(try ctx.fetchCount(FetchDescriptor<Clip>()) == 1)
        #expect(clip.linkedFolders.isEmpty)
        #expect(removed.isEmpty)
    }

    @Test func moveContentsUpToParent() throws {
        let home = try lib.createFolder(named: "Home2", in: nil)
        let turns = try lib.createFolder(named: "Turns", in: home)
        let sub = try lib.createFolder(named: "Sub", in: turns)
        let clip = try lib.filedClip(in: turns)
        try lib.deleteFolder(turns, mode: .moveContentsUp)
        #expect(clip.folder?.id == home.id)
        #expect(sub.parent?.id == home.id)
        #expect(removed.isEmpty)
    }

    // MARK: Clips

    @Test func clipsSortInTheOrderTheyWereMade() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let r = try lib.filedRecording()
        let a = try lib.filedClip("A", in: turns, on: r)
        let b = try lib.filedClip("B", in: turns, on: r)
        #expect(b.sortIndex > a.sortIndex)
    }

    @Test func updateRangeStaysInsideTheRecording() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let clip = try lib.filedClip(in: turns, on: try lib.filedRecording(duration: 10))
        try lib.updateRange(clip, start: 8, end: 30)
        #expect(clip.start == 8 && clip.end == 10)
    }

    @Test func moveClipBetweenFolders() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let spins = try lib.createFolder(named: "Spins", in: nil)
        let clip = try lib.filedClip(in: turns)
        try lib.moveClip(clip, to: spins)
        #expect(clip.folder?.id == spins.id)
        #expect(turns.clips.isEmpty)
    }

    @Test func infoTrimsAndCapsNote() throws {
        let clip = try lib.filedClip("Clip 1", in: try lib.createFolder(named: "Turns", in: nil))
        try lib.updateInfo(clip, name: "  ", note: String(repeating: "a", count: LibraryService.noteLimit + 60))
        #expect(clip.name == "Clip 1")
        #expect(clip.note?.count == LibraryService.noteLimit)
        try lib.updateInfo(clip, name: "Hammerlock", note: "   ")
        #expect(clip.name == "Hammerlock")
        #expect(clip.note == nil)
    }

    @Test func togglesAndPlayed() throws {
        let clip = try lib.filedClip(in: try lib.createFolder(named: "Turns", in: nil))
        try lib.toggleFavorite(clip)
        try lib.toggleLearned(clip)
        #expect(clip.isFavorite && clip.isLearned)
        let now = Date(timeIntervalSince1970: 100)
        try lib.markPlayed(clip, at: now)
        #expect(clip.lastPlayedAt == now)
    }

    @Test func normalizedClampsToTinyDuration() {
        #expect(ClipRange.normalized(start: 0, end: 0.1, duration: 0.3) == 0...0.3)
        #expect(ClipRange.normalized(start: 5, end: 2, duration: 10) == 2...5)
        #expect(ClipRange.normalized(start: -1, end: 0.2, duration: 10) == 0...0.5)
    }
}
