import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct ImportGuideFlowTests {
    let ctx: ModelContext
    let lib: LibraryService

    init() throws {
        ctx = try makeContext()
        lib = LibraryService(context: ctx)
    }

    @Test func freshVideoStartsAtTrimChoice() {
        let flow = ImportGuideFlow(clipCount: 0, hasWholeClip: false, keepWholeVideo: nil)
        #expect(flow.startStep == .trimChoice)
        #expect(flow.next(after: .trimChoice, usedWholeVideo: false) == .cut)
        #expect(flow.next(after: .cut, usedWholeVideo: false) == .keepWhole)
        #expect(flow.next(after: .keepWhole, usedWholeVideo: false) == .file)
        #expect(flow.next(after: .file, usedWholeVideo: false) == nil)
        #expect(flow.visibleSteps(usedWholeVideo: false) == [.trimChoice, .cut, .keepWhole, .file])
    }

    @Test func resumedWithClipsStartsAtCut() {
        #expect(ImportGuideFlow(clipCount: 2, hasWholeClip: false, keepWholeVideo: nil).startStep == .cut)
    }

    @Test func resumedWholeVideoOnlyStartsAtFile() {
        let flow = ImportGuideFlow(clipCount: 1, hasWholeClip: true, keepWholeVideo: nil)
        #expect(flow.usesWholeVideoOnly)
        #expect(flow.startStep == .file, "it was already named; only filing is left")
    }

    @Test func resumedWithClipsAndKeptVideoStartsAtCut() {
        let flow = ImportGuideFlow(clipCount: 3, hasWholeClip: true, keepWholeVideo: nil)
        #expect(!flow.usesWholeVideoOnly)
        #expect(flow.startStep == .cut)
        #expect(flow.next(after: .cut, usedWholeVideo: false) == .file, "the full video is already kept")
    }

    @Test func wholeVideoSkipsToFile() {
        let flow = ImportGuideFlow(clipCount: 0, hasWholeClip: false, keepWholeVideo: nil)
        #expect(flow.next(after: .trimChoice, usedWholeVideo: true) == .file)
        #expect(flow.visibleSteps(usedWholeVideo: true) == [.trimChoice, .file])
    }

    @Test func answeredKeepSkipsKeepStep() {
        let flow = ImportGuideFlow(clipCount: 2, hasWholeClip: false, keepWholeVideo: false)
        #expect(flow.next(after: .cut, usedWholeVideo: false) == .file)
        #expect(flow.visibleSteps(usedWholeVideo: false) == [.trimChoice, .cut, .file])
    }

    @Test func newClipsAfterAnswerAskAgain() throws {
        let r = try lib.addRecording(fileName: "a.mov", duration: 60, recordedAt: nil, photosAssetID: nil)
        _ = try lib.addClip(to: r, name: "A", instructors: [], start: 1, end: 3)
        try lib.setKeepWholeVideo(r, false)
        _ = try lib.addClip(to: r, name: "B", instructors: [], start: 5, end: 8)
        #expect(r.keepWholeVideo == nil, "a new clip changes what the full video is for")
        let flow = ImportGuideFlow(clipCount: r.clips.count, hasWholeClip: false, keepWholeVideo: r.keepWholeVideo)
        #expect(flow.next(after: .cut, usedWholeVideo: false) == .keepWhole)
    }

    @Test func folderDefaultsCarryDown() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let spins = try lib.createFolder(named: "Spins", in: nil)
        #expect(ImportGuideFlow.defaultFolder(previousInList: turns, lastUsed: spins)?.id == turns.id)
        #expect(ImportGuideFlow.defaultFolder(previousInList: nil, lastUsed: spins)?.id == spins.id)
        #expect(ImportGuideFlow.defaultFolder(previousInList: nil, lastUsed: nil) == nil)
    }

    @Test func changingAClipsFolderCarriesDownToClipsNotPickedByHand() throws {
        let salsa = try lib.createFolder(named: "Salsa", in: nil)
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let spins = try lib.createFolder(named: "Spins", in: nil)
        let ids = [UUID(), UUID(), UUID(), UUID()]
        func folders(_ picked: [UUID: Folder]) -> [UUID?] {
            let all = ImportGuideFlow.folders(for: ids, picked: picked, lastUsed: salsa)
            return ids.map { all[$0]?.id }
        }
        #expect(folders([:]) == [salsa.id, salsa.id, salsa.id, salsa.id], "all start in the last-used folder")
        #expect(folders([ids[0]: turns]) == [turns.id, turns.id, turns.id, turns.id],
                "picking the first moves the ones below it")
        #expect(folders([ids[0]: turns, ids[2]: spins]) == [turns.id, turns.id, spins.id, spins.id],
                "a clip picked by hand keeps its folder and leads the ones below")
        #expect(ImportGuideFlow.folders(for: ids, picked: [:], lastUsed: nil).isEmpty)
    }

    @Test func deletedLastFolderGivesNoDefault() throws {
        let gone = try lib.createFolder(named: "Gone", in: nil)
        try lib.deleteFolder(gone, mode: .deleteContents)
        #expect(ImportGuideFlow.defaultFolder(previousInList: nil, lastUsed: gone) == nil)
    }

    // MARK: Orphans

    @Test func topLevelDeleteMovesClipsToOrphans() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let a = try lib.filedClip("A", in: turns)
        try lib.deleteFolder(turns, mode: .moveContentsUp)
        let orphans = try #require(a.folder)
        #expect(orphans.isOrphans && orphans.name == "Orphans" && orphans.parent == nil)

        try lib.renameFolder(orphans, to: "Lost and found")
        let spins = try lib.createFolder(named: "Spins", in: nil)
        let b = try lib.filedClip("B", in: spins)
        try lib.deleteFolder(spins, mode: .moveContentsUp)
        #expect(b.folder?.id == orphans.id, "found again by its flag, not its name")
        #expect(try ctx.fetch(FetchDescriptor<Folder>()).filter(\.isOrphans).count == 1)
    }

    @Test func topLevelDeleteWithNoClipsMakesNoOrphans() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        _ = try lib.createFolder(named: "Sub", in: turns)
        try lib.deleteFolder(turns, mode: .moveContentsUp)
        #expect(try ctx.fetch(FetchDescriptor<Folder>()).filter(\.isOrphans).isEmpty)
    }

    @Test func nestedDeleteMovesClipsUp() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let sub = try lib.createFolder(named: "Sub", in: turns)
        let a = try lib.filedClip(in: sub)
        try lib.deleteFolder(sub, mode: .moveContentsUp)
        #expect(a.folder?.id == turns.id)
    }

    @Test func orphansOnlyDeletesContents() throws {
        let orphans = try lib.orphansFolder()
        #expect(throws: LibraryError.invalidMoveTarget) { try lib.deleteFolder(orphans, mode: .moveContentsUp) }
        try lib.deleteFolder(orphans, mode: .deleteContents)
        #expect(try ctx.fetchCount(FetchDescriptor<Folder>()) == 0)
    }

    @Test func orphansGoesLastOnHome() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let orphans = try lib.orphansFolder()
        #expect(orphans.sortIndex > a.sortIndex)
        #expect(try lib.orphansFolder().id == orphans.id)
    }
}
