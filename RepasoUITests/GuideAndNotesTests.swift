import XCTest

/// The how-to guide from Home, an empty Unsorted, a video's note on Full videos, and a clip's "Name & note…".
/// Needs `seed.mov` in the app's Documents folder (see DemoSeed); skipped otherwise.
@MainActor
final class GuideAndNotesTests: XCTestCase {
    private let app = XCUIApplication()

    func testGuideUnsortedInboxAndNotes() throws {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting", "-seedDemo", "-noLivePreviews"]
        app.launch()
        let turns = button(beginningWith: "Turns")
        guard turns.waitForExistence(timeout: 15) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }

        // The guide: open from ?, page through, finish
        app.buttons["How to use Repaso"].tap()
        XCTAssertTrue(app.staticTexts["Bring in your class videos"].waitForExistence(timeout: 3))
        snap("20-guide-first")
        for _ in 0..<5 { app.buttons["Next"].tap() }
        XCTAssertTrue(app.staticTexts["Find your way"].waitForExistence(timeout: 3))
        snap("21-guide-last")
        app.buttons["Start practising"].tap()
        XCTAssertTrue(app.buttons["New folder"].waitForExistence(timeout: 3), "the guide closes back to Home")

        // Unsorted only holds what still needs sorting: Saturday social has a clip (filed in Footwork), so nothing
        XCTAssertFalse(button(beginningWith: "Unsorted").exists, "nothing to sort, so no Unsorted tile")

        // Full videos: Saturday social is kept there. Edit details: its note shows on its card
        button(beginningWith: "Videos").tap()
        XCTAssertTrue(app.staticTexts["Saturday social"].waitForExistence(timeout: 5))
        snap("22-full-videos")
        app.staticTexts["Saturday social"].press(forDuration: 1.0)
        app.buttons["Edit details…"].tap()
        let note = app.textViews["Note"].exists ? app.textViews["Note"] : app.textFields["Note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap()
        note.typeText("Social: watch the lead's frame")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Social: watch the lead's frame"].waitForExistence(timeout: 4), "the note shows on the card")
        snap("23-video-note")

        // A clip's long-press menu offers Name & note
        app.buttons["Back to Home"].firstMatch.tap()
        turns.tap()
        let wrap = button(beginningWith: "Wrap and unwrap")
        XCTAssertTrue(wrap.waitForExistence(timeout: 5))
        wrap.press(forDuration: 1.0)
        app.buttons["Name & note…"].tap()
        XCTAssertTrue(app.staticTexts["Name & note"].waitForExistence(timeout: 3))
    }

    private func button(beginningWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
