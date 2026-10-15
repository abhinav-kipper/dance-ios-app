import XCTest

/// Drives the core loop on a seeded library and keeps a screenshot of each screen.
/// Needs `seed.mov` in the app's Documents folder (see DemoSeed); skipped otherwise.
@MainActor
final class WalkthroughTests: XCTestCase {
    private let app = XCUIApplication()

    func testCoreLoopWalkthrough() throws {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting", "-seedDemo"]
        app.launch()
        let turns = button(beginningWith: "Turns")
        guard turns.waitForExistence(timeout: 10) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }
        snap("01-home")

        // Folder
        turns.tap()
        let wrap = button(beginningWith: "Wrap and unwrap")
        XCTAssertTrue(wrap.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["In Hammerlock"].exists, "moved clip keeps its tag under the original")
        snap("02-folder")

        // Player
        wrap.tap()
        let close = app.buttons["Close player"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        sleep(2)
        snap("03-player")
        app.buttons["speed-0.5"].firstMatch.tap()
        app.buttons["Pause before repeat: none"].tap()
        sleep(1)
        snap("04-player-slow")
        close.tap()

        // Cut
        let cut = app.buttons["Cut clips from this video"].firstMatch
        XCTAssertTrue(cut.waitForExistence(timeout: 5))
        cut.tap()
        let markStart = app.buttons["Mark start"]
        XCTAssertTrue(markStart.waitForExistence(timeout: 5))
        snap("05-cut")
        markStart.tap()
        sleep(2)
        snap("06-cut-recording")
        button(beginningWith: "Mark end").tap()   // label also carries the live length
        XCTAssertTrue(app.staticTexts["Clip 4"].waitForExistence(timeout: 3), "new clip appears in the tray")
        snap("07-cut-clip-added")
        app.buttons["Done"].tap()

        // Move via long-press menu
        XCTAssertTrue(wrap.waitForExistence(timeout: 5))
        wrap.press(forDuration: 1.0)
        app.buttons["Move"].tap()
        let footwork = app.buttons["Footwork"].firstMatch
        XCTAssertTrue(footwork.waitForExistence(timeout: 3))
        footwork.tap()
        snap("08-move-sheet")
        app.buttons["Move to Footwork"].tap()
        sleep(2)
        snap("09-after-move")
        XCTAssertTrue(app.staticTexts["In Footwork"].waitForExistence(timeout: 3))
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
