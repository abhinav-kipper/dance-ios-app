import XCTest

/// Swipe back and the back-button menu, a folder made from the Move sheet, and Cut's scrolling strip and swipe-to-close.
/// Needs `seed.mov` in the app's Documents folder (see DemoSeed); skipped otherwise.
@MainActor
final class NavigationAndCutTests: XCTestCase {
    private let app = XCUIApplication()

    func testSwipeBackMenuNewFolderAndCutStrip() throws {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting", "-seedDemo", "-noLivePreviews"]
        app.launch()
        let turns = button(beginningWith: "Turns")
        guard turns.waitForExistence(timeout: 15) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }
        let newFolderOnHome = app.buttons["New folder"]

        // Swipe from the left edge goes back
        turns.tap()
        XCTAssertTrue(app.buttons["Back to Home"].waitForExistence(timeout: 5))
        swipeBackFromEdge()
        XCTAssertTrue(newFolderOnHome.waitForExistence(timeout: 3), "edge swipe returns Home")

        // Two levels down, press and hold Back to jump straight Home
        turns.tap()
        let hammerlock = button(beginningWith: "Hammerlock,")
        XCTAssertTrue(hammerlock.waitForExistence(timeout: 5))
        hammerlock.tap()
        let back = app.buttons["Back to Turns"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.press(forDuration: 1.0)
        let homeItem = app.buttons["Home"].firstMatch
        XCTAssertTrue(homeItem.waitForExistence(timeout: 3), "holding Back lists the levels above")
        snap("15-back-menu")
        homeItem.tap()
        XCTAssertTrue(newFolderOnHome.waitForExistence(timeout: 3), "the menu jumps straight Home")

        // Make a folder from the Move sheet and move a clip into it
        turns.tap()
        let prep = button(beginningWith: "Double turn prep")
        XCTAssertTrue(prep.waitForExistence(timeout: 5))
        prep.press(forDuration: 1.0)
        app.buttons["Move to folder…"].tap()
        let newFolder = app.buttons["New folder"].firstMatch
        XCTAssertTrue(newFolder.waitForExistence(timeout: 3))
        newFolder.tap()
        let nameField = app.alerts.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.typeText("Spins")
        snap("16-new-folder-alert")
        app.alerts.buttons["Create"].tap()
        let moveTo = app.buttons["Move to Spins"]
        XCTAssertTrue(moveTo.waitForExistence(timeout: 3), "the new folder is selected, ready to move into")
        moveTo.tap()
        XCTAssertTrue(app.staticTexts["Moved to Spins"].firstMatch.waitForExistence(timeout: 4))

        // Cut (via Trim… on a clip): scrolling the strip moves the video
        let wrap = button(beginningWith: "Wrap and unwrap")
        XCTAssertTrue(wrap.waitForExistence(timeout: 5))
        wrap.press(forDuration: 1.0)
        app.buttons["Trim…"].tap()
        let playhead = app.descendants(matching: .any)["Playhead"].firstMatch
        XCTAssertTrue(playhead.waitForExistence(timeout: 5))
        let before = playhead.value as? String
        let mid = playhead.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Start between the selected clip's handles (at the playhead and ~130pt right), so it scrolls, not trims
        mid.withOffset(CGVector(dx: 70, dy: 0))
            .press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: -110, dy: 0)), withVelocity: .slow,
                   thenHoldForDuration: 0.3)
        XCTAssertTrue(waitForValue(of: playhead, toDifferFrom: before), "scrolling the strip moves the time")
        snap("17-cut-strip-scrolled")

        // Pull the video down to close Cut
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 320)), withVelocity: .fast,
                  thenHoldForDuration: 0)
        XCTAssertTrue(playhead.waitForNonExistence(timeout: 4), "swiping the video down closes Cut")
    }

    private func swipeBackFromEdge() {
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)),
                   withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func waitForValue(of element: XCUIElement, toDifferFrom old: String?, timeout: TimeInterval = 4) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if element.value as? String != old { return true }
            RunLoop.current.run(until: .now.addingTimeInterval(0.2))
        }
        return false
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
