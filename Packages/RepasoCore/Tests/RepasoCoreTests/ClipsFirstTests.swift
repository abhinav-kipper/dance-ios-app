import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct ClipsFirstTests {
    let ctx: ModelContext
    let lib: LibraryService

    init() throws {
        ctx = try makeContext()
        lib = LibraryService(context: ctx)
    }

    func video(_ title: String = "Class", in folder: Folder?) throws -> Original {
        try lib.addOriginal(title: title, fileName: "\(title).mov", duration: 120, recordedAt: nil, to: folder)
    }

    @Test func clipsLiveWhereTheyAreFiled() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let hammer = try lib.createFolder(named: "Hammerlock", in: turns)
        let o = try video(in: turns)
        let a = try lib.addClip(to: o, start: 1, end: 3)
        let b = try lib.addClip(to: o, start: 5, end: 8)
        try lib.moveClip(b, to: hammer)
        #expect(FolderContents.folderClips(in: turns, sort: .manual, hideLearned: false).map(\.id) == [a.id])
        #expect(FolderContents.folderClips(in: hammer, sort: .manual, hideLearned: false).map(\.id) == [b.id])
        #expect(FolderContents.clipCount(in: turns) == 2, "a folder counts its subfolders' clips too")
        #expect(FolderContents.clipCount(in: hammer) == 1)
    }

    @Test func linkedClipsAndLinkedVideosShowAfterHomeClips() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let teacher = try lib.createFolder(named: "Ataca", in: nil)
        let o1 = try video("One", in: turns)
        let o2 = try video("Two", in: nil)
        let c1 = try lib.addClip(to: o1, start: 1, end: 3)
        let c2 = try lib.addClip(to: o2, start: 1, end: 3)
        let home = try lib.addClip(to: try video("Three", in: teacher), start: 1, end: 3)
        try lib.setLinks(c1, to: [teacher])
        try lib.setLinks(o2, to: [teacher])
        let shown = FolderContents.folderClips(in: teacher, sort: .manual, hideLearned: false).map(\.id)
        #expect(shown.first == home.id)
        #expect(Set(shown) == [home.id, c1.id, c2.id])
        #expect(FolderContents.showsThroughLink(c1, in: teacher))
        #expect(FolderContents.showsThroughLink(c2, in: teacher))
        #expect(!FolderContents.showsThroughLink(home, in: teacher))
    }

    @Test func videosWaitToBeCutUntilTheyHaveClips() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let fresh = try video("Fresh", in: turns)
        let cut = try video("Cut", in: turns)
        _ = try lib.addClip(to: cut, start: 1, end: 3)
        #expect(FolderContents.videosToCut(in: turns, sort: .manual).map(\.id) == [fresh.id])
        let loose = try video("Loose", in: nil)
        #expect(FolderContents.unsortedVideosToCut([loose, fresh], sort: .manual).map(\.id) == [loose.id])
    }

    @Test func unsortedListsUnfiledClipsOfUnsortedVideos() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o = try video(in: nil)
        let a = try lib.addClip(to: o, start: 1, end: 3)
        let b = try lib.addClip(to: o, start: 5, end: 8)
        try lib.moveClip(b, to: turns)
        let inTurns = try lib.addClip(to: try video("Other", in: turns), start: 1, end: 2)
        let all = try ctx.fetch(FetchDescriptor<Original>())
        #expect(FolderContents.unsortedClips(of: all, sort: .manual, hideLearned: false).map(\.id) == [a.id])
        #expect(!FolderContents.unsortedClips(of: all, sort: .manual, hideLearned: false).contains { $0.id == inTurns.id })
    }

    @Test func detachingKeepsTheClipWhereItWasAndLetsTheVideoGo() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let teacher = try lib.createFolder(named: "Ataca", in: nil)
        let o = try video(in: turns)
        o.instructors = ["Ataca"]
        let clip = try lib.addClip(to: o, start: 10, end: 14)
        try lib.updateInfo(clip, name: "Hammerlock", note: "Low hand")
        try lib.toggleFavorite(clip)
        try lib.setLinks(clip, to: [teacher])

        try lib.detach(clip, intoFile: "hammerlock.mp4", duration: 4)
        try lib.deleteOriginal(o)

        #expect(clip.original?.fileName == "hammerlock.mp4")
        #expect(clip.original?.isClipSource == true)
        #expect(clip.original?.instructors == ["Ataca"])
        #expect(clip.start == 0 && clip.end == 4)
        #expect(clip.name == "Hammerlock" && clip.note == "Low hand" && clip.isFavorite)
        #expect(FolderContents.folderClips(in: turns, sort: .manual, hideLearned: false).map(\.id) == [clip.id])
        #expect(FolderContents.showsThroughLink(clip, in: teacher))
        let videos = FolderContents.allVideos(try ctx.fetch(FetchDescriptor<Original>()))
        #expect(videos.isEmpty, "a clip's own short video isn't listed as a full video")
        #expect(FolderContents.videosToCut(in: turns, sort: .manual).isEmpty)
    }
}
