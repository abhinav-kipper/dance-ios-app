import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct GuidedImportTests {
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

    func pending(_ fileName: String = "class.mov", duration: Double = 120) throws -> Recording {
        try lib.addRecording(fileName: fileName, duration: duration, recordedAt: nil, photosAssetID: "asset-1")
    }

    // MARK: Model

    @Test func newRecordingsWaitInTheGuide() throws {
        let a = try pending("a.mov")
        let b = try pending("b.mov")
        #expect(a.isPending && b.isPending)
        #expect(a.photosAssetID == "asset-1")
        #expect(b.sortIndex > a.sortIndex)
        #expect(try FolderContents.pendingRecordings(ctx).map(\.id) == [a.id, b.id])
    }

    @Test func addClipNeedsAName() throws {
        let r = try pending()
        #expect(throws: LibraryError.emptyName) {
            try lib.addClip(to: r, name: "  ", instructors: [], start: 1, end: 3)
        }
        let clip = try lib.addClip(to: r, name: "  Backazouk ", instructors: [" Ataca ", "ataca", "Alemana"], start: 1, end: 3)
        #expect(clip.name == "Backazouk")
        #expect(clip.instructors == ["Ataca", "Alemana"])
        #expect(clip.folder == nil, "folders are chosen at the last step")
        #expect(r.clips.count == 1)
    }

    @Test func addClipNormalisesRange() throws {
        let r = try pending(duration: 10)
        let clip = try lib.addClip(to: r, name: "End", instructors: [], start: 9.9, end: 9.8)
        #expect(clip.start == 9.5 && clip.end == 10)
    }

    @Test func wholeClipCoversRecording() throws {
        let r = try pending(duration: 120)
        let whole = try lib.addWholeClip(to: r, name: "Thursday class", instructors: [])
        #expect(whole.start == 0 && whole.end == 120)
        #expect(whole.coversWholeRecording)
        let part = try lib.addClip(to: r, name: "Turn", instructors: [], start: 1, end: 3)
        #expect(!part.coversWholeRecording)
        let nearly = try lib.addClip(to: r, name: "Nearly", instructors: [], start: 0.03, end: 119.97)
        #expect(nearly.coversWholeRecording, "within 0.05s counts as whole")
    }

    @Test func cascadeDeletesClips() throws {
        let r = try pending()
        _ = try lib.addClip(to: r, name: "Turn", instructors: [], start: 1, end: 3)
        ctx.delete(r)
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<Clip>()) == 0)
    }

    @Test func thumbnailsAndPreviewsUseTheRecordingsFile() throws {
        let r = try pending("x.mov", duration: 100)
        #expect(r.thumbnailRequest.time == 30)
        let clip = try lib.addClip(to: r, name: "Turn", instructors: [], start: 10, end: 20)
        #expect(clip.thumbnailRequest?.time == 13)
        #expect(clip.thumbnailRequest?.fileName == "x.mov")
        #expect(clip.previewSource?.range == 10...13)
    }

    // MARK: Hidden while pending

    @Test func pendingClipsAreHidden() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let r = try pending()
        let clip = try lib.addClip(to: r, name: "Hammerlock", instructors: [], start: 1, end: 3)
        try lib.moveClip(clip, to: turns)
        try lib.toggleFavorite(clip)
        #expect(FolderContents.folderClips(in: turns, sort: .manual, hideLearned: false).isEmpty)
        #expect(FolderContents.clipCount(in: turns) == 0)
        #expect(FolderContents.mosaic(for: turns).isEmpty)
        #expect(try FolderContents.favorites(ctx, sort: .manual).isEmpty)
        let found = LibrarySearch.results(for: "hammer", clips: try ctx.fetch(FetchDescriptor<Clip>()),
                                          folders: try ctx.fetch(FetchDescriptor<Folder>()))
        #expect(found.clips.isEmpty)

        r.isPending = false
        try ctx.save()
        #expect(FolderContents.folderClips(in: turns, sort: .manual, hideLearned: false).map(\.id) == [clip.id])
    }

    // MARK: Files

    @Test func deletingLastClipRemovesFile() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let r = try lib.filedRecording("class.mov")
        let a = try lib.filedClip("A", in: turns, on: r)
        let b = try lib.filedClip("B", in: turns, on: r)
        try lib.deleteClip(a)
        #expect(removed.isEmpty, "the other clip still uses the file")
        try lib.deleteClip(b)
        #expect(removed == ["class.mov"])
        #expect(try ctx.fetchCount(FetchDescriptor<Recording>()) == 0)
    }

    // MARK: Suggestions

    @Test func nameSuggestions() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let same = Date(timeIntervalSince1970: 100)
        for name in ["Backazouk", "Back basic", "Pasitos", "backazouk"] {
            try lib.filedClip(name, in: turns).addedAt = same
        }
        let clips = try ctx.fetch(FetchDescriptor<Clip>())
        #expect(TagSuggestions.names(for: "Back", in: clips) == ["Backazouk", "Back basic"],
                "used twice first, then alphabetical; one spelling per name")
        #expect(TagSuggestions.names(for: "pas", in: clips) == ["Pasitos"])
    }

    @Test func instructorSuggestionsComeFromClips() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        _ = try lib.filedClip("A", in: turns, instructors: ["Ataca & Alemana"])
        _ = try lib.filedClip("B", in: turns, instructors: ["Ataca & Alemana", "Sara"])
        let clips = try ctx.fetch(FetchDescriptor<Clip>())
        #expect(TagSuggestions.instructors(for: "", in: clips).first == "Ataca & Alemana")
        #expect(TagSuggestions.instructors(for: "sa", in: clips) == ["Sara"])
    }

    @Test func setInstructorsNormalises() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let clip = try lib.filedClip(in: turns)
        try lib.setInstructors(clip, [" Marco ", "marco", "", "Sara"])
        #expect(clip.instructors == ["Marco", "Sara"])
    }

    // MARK: Finish

    @Test func finishNeedsEveryFolder() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let spins = try lib.createFolder(named: "Spins", in: nil)
        let r = try pending()
        let a = try lib.addClip(to: r, name: "A", instructors: [], start: 1, end: 3)
        let b = try lib.addClip(to: r, name: "B", instructors: [], start: 5, end: 8)
        #expect(throws: LibraryError.missingFolder) { try lib.finish(r, folders: [a.id: turns]) }
        #expect(r.isPending)
        #expect(a.folder == nil, "nothing is filed until every clip has a folder")
        try lib.finish(r, folders: [a.id: turns, b.id: spins])
        #expect(!r.isPending)
        #expect(a.folder?.id == turns.id && b.folder?.id == spins.id)
        #expect(throws: LibraryError.notPending) { try lib.finish(r, folders: [a.id: turns, b.id: spins]) }
    }

    @Test func keepAnswerIsStored() throws {
        let r = try pending()
        try lib.setKeepWholeVideo(r, false)
        #expect(r.keepWholeVideo == false)
        try lib.setKeepWholeVideo(r, nil)
        #expect(r.keepWholeVideo == nil)
    }

    @Test func clipsNeedingOwnFilesLeaveOutTheWholeClip() throws {
        let r = try pending()
        let whole = try lib.addWholeClip(to: r, name: "Full", instructors: [])
        let a = try lib.addClip(to: r, name: "A", instructors: [], start: 1, end: 3)
        #expect(lib.clipsNeedingOwnFiles(r).map(\.id) == [a.id])
        #expect(!lib.clipsNeedingOwnFiles(r).contains { $0.id == whole.id })
    }

    // MARK: Own files

    @Test func ownFilesKeepEverything() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let teacher = try lib.createFolder(named: "Ataca", in: nil)
        let r = try lib.filedRecording("class.mov")
        let clip = try lib.filedClip("Hammerlock", in: turns, on: r, start: 10, end: 14, instructors: ["Ataca"])
        try lib.setNote(clip, "Low hand")
        try lib.toggleFavorite(clip)
        try lib.toggleLearned(clip)
        try lib.setLinks(clip, to: [teacher])
        try lib.setFraming(clip, Framing(zoom: 2, panX: 0.5, panY: 0))

        try lib.adoptOwnFiles([.init(clipID: clip.id, fileName: "hammerlock.mp4", duration: 4)], from: r)

        #expect(clip.recording?.fileName == "hammerlock.mp4")
        #expect(clip.recording?.isPending == false)
        #expect(clip.start == 0 && clip.end == 4)
        #expect(clip.name == "Hammerlock" && clip.note == "Low hand" && clip.isFavorite && clip.isLearned)
        #expect(clip.instructors == ["Ataca"])
        #expect(clip.folder?.id == turns.id && clip.linkedFolders.map(\.id) == [teacher.id])
        #expect(clip.framing == Framing(zoom: 2, panX: 0.5, panY: 0))
        #expect(removed == ["class.mov"], "the old video had no clips left")
        #expect(try ctx.fetch(FetchDescriptor<Recording>()).map(\.fileName) == ["hammerlock.mp4"])
    }

    @Test func ownFilesStayPending() throws {
        let r = try pending()
        let a = try lib.addClip(to: r, name: "A", instructors: [], start: 1, end: 3)
        try lib.adoptOwnFiles([.init(clipID: a.id, fileName: "a.mp4", duration: 2)], from: r)
        #expect(a.recording?.isPending == true, "still in the guide until Finish")
        #expect(a.recording?.photosAssetID == nil)
    }

    @Test func failedExportLeavesNothing() throws {
        let r = try pending()
        let a = try lib.addClip(to: r, name: "A", instructors: [], start: 1, end: 3)
        #expect(throws: (any Error).self) {
            try lib.adoptOwnFiles([.init(clipID: a.id, fileName: "a.mp4", duration: 2),
                                   .init(clipID: UUID(), fileName: "x.mp4", duration: 2)], from: r)
        }
        #expect(a.recording?.id == r.id && a.start == 1)
        #expect(r.isPending && r.clips.count == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<Recording>()) == 1)
        #expect(removed.isEmpty)
    }

    @Test func deleteWholeClipKeepsSiblings() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let r = try lib.filedRecording("class.mov")
        let whole = try lib.filedClip("Full", in: turns, on: r, start: 0, end: 120)
        let a = try lib.filedClip("A", in: turns, on: r, start: 1, end: 3)
        let b = try lib.filedClip("B", in: turns, on: r, start: 5, end: 8)
        try lib.deleteWholeClip(whole, siblingsMovedTo: [.init(clipID: a.id, fileName: "a.mp4", duration: 2),
                                                         .init(clipID: b.id, fileName: "b.mp4", duration: 3)])
        #expect(try ctx.fetchCount(FetchDescriptor<Recording>()) == 2)
        #expect(Set(try ctx.fetch(FetchDescriptor<Clip>()).map(\.id)) == [a.id, b.id])
        #expect(removed == ["class.mov"])
    }

    // MARK: Unsorted

    @Test func deletePendingRemovesAll() throws {
        let r = try pending("class.mov")
        _ = try lib.addClip(to: r, name: "A", instructors: [], start: 1, end: 3)
        try lib.deletePending(r)
        #expect(try ctx.fetchCount(FetchDescriptor<Recording>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<Clip>()) == 0)
        #expect(removed == ["class.mov"])
        let filed = try lib.filedRecording()
        #expect(throws: LibraryError.notPending) { try lib.deletePending(filed) }
    }

    @Test func finishWithOwnFilesFilesThemAndDropsTheVideo() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let r = try pending("class.mov")
        let a = try lib.addClip(to: r, name: "A", instructors: [], start: 1, end: 3)
        try lib.finish(r, folders: [a.id: turns], ownFiles: [.init(clipID: a.id, fileName: "a.mp4", duration: 2)])
        #expect(a.folder?.id == turns.id)
        #expect(a.recording?.fileName == "a.mp4" && a.recording?.isPending == false)
        #expect(removed == ["class.mov"])
        #expect(FolderContents.folderClips(in: turns, sort: .manual, hideLearned: false).map(\.id) == [a.id])
    }

    @Test func finishWithABadOwnFileChangesNothing() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let r = try pending()
        let a = try lib.addClip(to: r, name: "A", instructors: [], start: 1, end: 3)
        #expect(throws: LibraryError.unknownClip) {
            try lib.finish(r, folders: [a.id: turns], ownFiles: [.init(clipID: UUID(), fileName: "x.mp4", duration: 2)])
        }
        #expect(r.isPending && a.folder == nil)
    }
}
