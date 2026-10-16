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
    @Test func recordedLine() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let oct12 = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10)))
        let oct9 = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 10)))
        #expect(ImportSummary.recordedLine([], calendar: cal, locale: locale) == nil)
        #expect(ImportSummary.recordedLine([oct12, oct12], calendar: cal, locale: locale) == "Recorded Oct 12, 2026")
        let span = try #require(ImportSummary.recordedLine([oct12, oct9], calendar: cal, locale: locale))
        #expect(span.hasPrefix("Recorded Oct 9"))
        #expect(span.hasSuffix("12, 2026"))
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
        let old = Date(timeIntervalSince1970: 0)
        let o1 = try lib.addOriginal(title: "1", fileName: "1", duration: 1, recordedAt: nil, to: nil, instructors: ["Marco & Sara"], event: "Berlin 2026")
        let o2 = try lib.addOriginal(title: "2", fileName: "2", duration: 1, recordedAt: nil, to: nil, instructors: ["Marco & Sara", "Studio team"], event: "Thursday class")
        let o3 = try lib.addOriginal(title: "3", fileName: "3", duration: 1, recordedAt: nil, to: nil, instructors: ["Ataca & Alemana"], event: "berlin 2026")
        o1.importedAt = old
        let all = [o1, o2, o3]
        #expect(TagSuggestions.instructors(for: "", in: all) == ["Marco & Sara", "Ataca & Alemana", "Studio team"])
        #expect(TagSuggestions.events(for: "", in: all).first?.lowercased() == "berlin 2026")
        #expect(TagSuggestions.events(for: "", in: all).count == 2)
    }
    @Test func suggestionsPreferPrefixThenSubstringAndExclude() throws {
        let ctx = try makeContext()
        let lib = LibraryService(context: ctx)
        let o = try lib.addOriginal(title: "1", fileName: "1", duration: 1, recordedAt: nil, to: nil,
                                    instructors: ["Sara Lee", "Ataca & Alemana", "Alex"], event: nil)
        #expect(TagSuggestions.instructors(for: "al", in: [o]) == ["Alex", "Ataca & Alemana"])
        #expect(TagSuggestions.instructors(for: "a", excluding: ["Alex"], in: [o], limit: 1) == ["Ataca & Alemana"])
        #expect(TagSuggestions.instructors(for: "alex", in: [o]).isEmpty)
        #expect(TagSuggestions.instructors(for: "ee", in: [o]) == ["Sara Lee"])
    }
}
