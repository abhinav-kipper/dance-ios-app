import XCTest

/// The how-to guide from Home, Unsorted holding a video left half-way, and a clip's "Name & note…".
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
        XCTAssertTrue(app.staticTexts["Tap Import, pick your class videos"].waitForExistence(timeout: 3))
        snap("20-guide-first")
        for _ in 0..<4 { app.buttons["Next"].tap() }
        XCTAssertTrue(app.staticTexts["Tap Arrange, then hold and drag"].waitForExistence(timeout: 3))
        snap("21-guide-last")
        app.buttons["Start practising"].tap()
        XCTAssertTrue(app.buttons["New folder"].waitForExistence(timeout: 3), "the guide closes back to Home")

        // Unsorted holds the video left half-way through the guide (Sunday, one clip named)
        let unsorted = button(beginningWith: "Unsorted, 1 video")
        XCTAssertTrue(unsorted.exists, "a video still to go through shows the Unsorted tile")
        unsorted.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "1 clip so far")).firstMatch
            .waitForExistence(timeout: 5), "with what was made so far")
        snap("22-unsorted")

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
