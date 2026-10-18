import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct NotesAndInboxTests {
    let ctx: ModelContext
    let lib: LibraryService

    init() throws {
        ctx = try makeContext()
        lib = LibraryService(context: ctx)
    }

    @Test func videoDetailsSaveTrimAndClear() throws {
        let o = try lib.addOriginal(title: "Class", fileName: "c.mov", duration: 60, recordedAt: nil, to: nil)
        try lib.updateDetails(o, title: "  Sensual basics ", note: "  Keep the frame soft  ",
                              instructors: ["Ataca", "ataca", "Alemana"], event: " Berlin ")
        #expect(o.title == "Sensual basics")
        #expect(o.note == "Keep the frame soft")
        #expect(o.instructors == ["Ataca", "Alemana"])
        #expect(o.event == "Berlin")

        try lib.updateDetails(o, title: "   ", note: "", instructors: [], event: "")
        #expect(o.title == "Sensual basics", "a blank title keeps the old one")
        #expect(o.note == nil)
        #expect(o.instructors.isEmpty)
        #expect(o.event == nil)
    }

    @Test func videoNoteIsCappedLikeClipNotes() throws {
        let o = try lib.addOriginal(title: "Class", fileName: "c.mov", duration: 60, recordedAt: nil, to: nil)
        try lib.updateDetails(o, title: "Class", note: String(repeating: "x", count: LibraryService.noteLimit + 300), instructors: [], event: nil)
        #expect(o.note?.count == LibraryService.noteLimit)
    }

    @Test func importTagsPreferTheVideosOwnValue() {
        #expect(TagText.resolved("Ataca", shared: "Kike") == "Ataca")
        #expect(TagText.resolved(nil, shared: "Kike") == "Kike")
        #expect(TagText.resolved("   ", shared: "Kike") == "Kike")
    }

    @Test func unsortedListsOnlyUnfiledClips() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o = try lib.addOriginal(title: "Class", fileName: "c.mov", duration: 60, recordedAt: nil, to: nil)
        let a = try lib.addClip(to: o, start: 1, end: 3)
        let b = try lib.addClip(to: o, start: 5, end: 8)
        try lib.moveClip(b, to: turns)
        #expect(FolderContents.unfiledClips(of: o, sort: .manual, hideLearned: false).map(\.id) == [a.id])
        #expect(FolderContents.filedCount(of: o) == 1)
        #expect(FolderContents.clips(of: o, sort: .manual, hideLearned: false).count == 2, "folders still list both")
    }

    @Test func placeKeepsHomeWhenTickedAndMovesOtherwise() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let teacher = try lib.createFolder(named: "Ataca", in: nil)
        let spins = try lib.createFolder(named: "Spins", in: nil)
        let o = try lib.addOriginal(title: "Class", fileName: "c.mov", duration: 60, recordedAt: nil, to: turns)
        let clip = try lib.addClip(to: o, start: 1, end: 3)

        try lib.place(clip, in: [teacher, turns])
        #expect(clip.effectiveFolder?.id == turns.id, "still lives with its video in Turns")
        #expect(clip.linkedFolders.map(\.id) == [teacher.id])

        try lib.place(clip, in: [spins, teacher])
        #expect(clip.effectiveFolder?.id == spins.id, "Turns unticked: it moves to the first ticked folder")
        #expect(clip.linkedFolders.map(\.id) == [teacher.id])

        try lib.place(clip, in: [])
        #expect(clip.folder == nil && clip.effectiveFolder?.id == turns.id, "nothing ticked: back with its video")
        #expect(clip.linkedFolders.isEmpty)
    }

    @Test func placeVideoAndNotes() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let teacher = try lib.createFolder(named: "Ataca", in: nil)
        let o = try lib.addOriginal(title: "Class", fileName: "c.mov", duration: 60, recordedAt: nil, to: nil)
        try lib.place(o, in: [turns, teacher])
        #expect(o.folder?.id == turns.id && o.linkedFolders.map(\.id) == [teacher.id])
        try lib.place(o, in: [])
        #expect(o.folder == nil && o.linkedFolders.isEmpty)

        let clip = try lib.addClip(to: o, start: 1, end: 3)
        try lib.setNote(clip, "  Count 5: hand on her shoulder blade  ")
        try lib.setNote(o, "Social, slow song")
        #expect(clip.note == "Count 5: hand on her shoulder blade")
        #expect(o.note == "Social, slow song")
        try lib.setNote(clip, "   ")
        #expect(clip.note == nil)
    }
}
