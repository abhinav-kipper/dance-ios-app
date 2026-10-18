import Testing
import Foundation
import SwiftData
@testable import RepasoCore

struct HelperTests {
    let a = UUID(), b = UUID(), c = UUID()

    @Test func movingForwardLandsAfterTarget() {
        #expect(FolderOrder.moving(a, onto: c, in: [a, b, c]) == [b, c, a])
    }
    @Test func movingBackwardLandsBeforeTarget() {
        #expect(FolderOrder.moving(c, onto: a, in: [a, b, c]) == [c, a, b])
    }
    @Test func movingOntoItselfOrUnknownIsUnchanged() {
        #expect(FolderOrder.moving(a, onto: a, in: [a, b]) == [a, b])
        #expect(FolderOrder.moving(UUID(), onto: a, in: [a, b]) == [a, b])
    }
    @Test func photosPromptText() {
        #expect(PhotosCleanupText.prompt(count: 3) == "Delete 3 videos from Photos?")
        #expect(PhotosCleanupText.prompt(count: 1) == "Delete this video from Photos?")
    }
}

@MainActor
struct TagTests {
    @Test func instructorsSplitTrimAndDedupe() {
        #expect(TagText.instructors(from: "marco, Marco ,, Sara ") == ["marco", "Sara"])
    }
    @Test func lastTokenAndCompletion() {
        #expect(TagText.lastToken(of: "Marco, At") == "At")
        #expect(TagText.completing("Marco, At", with: "Ataca & Alemana") == "Marco, Ataca & Alemana, ")
        #expect(TagText.completing("", with: "Sara") == "Sara, ")
    }
    @Test func suggestionsRankByUseThenRecency() throws {
        let ctx = try makeContext()
        let lib = LibraryService(context: ctx)
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let c1 = try lib.filedClip("1", in: turns, instructors: ["Marco & Sara"])
        _ = try lib.filedClip("2", in: turns, instructors: ["Marco & Sara", "Studio team"])
        _ = try lib.filedClip("3", in: turns, instructors: ["Ataca & Alemana"])
        c1.addedAt = Date(timeIntervalSince1970: 0)
        let all = try ctx.fetch(FetchDescriptor<Clip>())
        #expect(TagSuggestions.instructors(for: "", in: all).first == "Marco & Sara")
        #expect(TagSuggestions.instructors(for: "", in: all).count == 3)
    }
    @Test func suggestionsPreferPrefixThenSubstringAndExclude() throws {
        let ctx = try makeContext()
        let lib = LibraryService(context: ctx)
        let c = try lib.filedClip(in: try lib.createFolder(named: "Turns", in: nil),
                                  instructors: ["Sara Lee", "Ataca & Alemana", "Alex"])
        #expect(TagSuggestions.instructors(for: "al", in: [c]) == ["Alex", "Ataca & Alemana"])
        #expect(TagSuggestions.instructors(for: "a", excluding: ["Alex"], in: [c], limit: 1) == ["Ataca & Alemana"])
        #expect(TagSuggestions.instructors(for: "alex", in: [c]).isEmpty)
        #expect(TagSuggestions.instructors(for: "ee", in: [c]) == ["Sara Lee"])
    }
}
