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
        app.openClipDecks()
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
        app.showPlayerControls()
        app.buttons["speed-0.5"].firstMatch.tap()
        app.buttons["Pause before repeat: none"].tap()
        sleep(1)
        snap("04-player-slow")

        // Rename the clip by tapping its name in the panel (paused first, so the panel doesn't slide away mid-step)
        app.descendants(matching: .any)["Video"].firstMatch.tap()
        app.showPlayerControls()
        app.descendants(matching: .any)["player-clip-name"].firstMatch.tap()   // the Player's label, not the list behind
        let nameField = app.textFields["Clip name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "tapping the name starts renaming")
        nameField.typeText("Wrap and unwrap\n")
        XCTAssertTrue(app.staticTexts["Wrap and unwrap"].waitForExistence(timeout: 3))

        // Hold the right side: steps forward frame by frame, then stays paused on that frame with the chip
        let videoElement = app.descendants(matching: .any)["Video"].firstMatch
        videoElement.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.35)).press(forDuration: 1.2)
        let frameChip = app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", " seconds")).firstMatch
        XCTAssertTrue(frameChip.waitForExistence(timeout: 2), "holding a side shows the step chip")
        XCTAssertEqual(videoElement.label, "Play", "after stepping it stays paused")
        snap("04-hold-step")
        videoElement.tap()   // play again

        // The panel slides down to its grabber while playing; drag it back up
        let showControls = app.buttons["Show controls"]
        XCTAssertTrue(showControls.waitForExistence(timeout: 6), "panel slides away when idle")
        snap("04a-player-panel-hidden")
        showControls.tap()
        XCTAssertTrue(app.buttons["Hide controls"].waitForExistence(timeout: 3))

        // Swipe to another clip in the folder and back
        let video = app.descendants(matching: .any)["Video"].firstMatch
        let pill = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Turns ")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 3))
        let firstPosition = pill.label
        video.swipeDown()   // "Wrap and unwrap" is last in the folder, so go back one
        XCTAssertTrue(waitForLabel(of: pill, toDifferFrom: firstPosition), "swiping changes the clip")
        snap("04b-player-swiped")
        // On the picture, above the panel: a drag that starts on the timeline scrubs instead
        let upper = video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        upper.press(forDuration: 0.05, thenDragTo: upper.withOffset(CGVector(dx: 0, dy: -260)), withVelocity: .fast,
                    thenHoldForDuration: 0)
        XCTAssertTrue(waitForLabel(of: pill, toBe: firstPosition), "swiping the other way comes back")

        // Pinch to zoom, then reset
        video.pinch(withScale: 2, velocity: 1)
        let reset = app.buttons["Reset zoom"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3), "zooming shows the reset chip")
        snap("04c-player-zoomed")
        reset.tap()
        XCTAssertTrue(reset.waitForNonExistence(timeout: 3))

        // Pause, then drag sideways to step frames
        video.tap()
        let mid = video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: 60, dy: 0)))
        let chip = app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", " seconds")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 2), "frame stepping shows the step chip")
        snap("04d-player-frame-step")
        video.tap()   // stepping keeps the top bar away; playing brings it back
        XCTAssertTrue(close.waitForExistence(timeout: 3) && close.isHittable)
        close.tap()

        // Whole video from its thumbnail
        let playWhole = app.buttons["Play whole video"].firstMatch
        XCTAssertTrue(playWhole.waitForExistence(timeout: 5))
        playWhole.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Share clip"].exists, "whole videos have no clip buttons (favorite, learned, share)")
        snap("04e-player-whole-video")
        app.buttons["Close player"].tap()

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
        // Name it straight away from the toast
        let nameButton = app.buttons["Name"].firstMatch   // the folder behind Cut hosts the same toast
        XCTAssertTrue(nameButton.waitForExistence(timeout: 3), "the clip-added toast offers Name")
        nameButton.tap()
        let trayField = app.textFields["Clip name"]
        XCTAssertTrue(trayField.waitForExistence(timeout: 3))
        trayField.typeText("Basic step\n")
        XCTAssertTrue(app.staticTexts["Basic step"].waitForExistence(timeout: 3), "typing replaces the clip's name")
        app.buttons["Done"].tap()

        // Drag a clip onto a subfolder card, then Undo
        XCTAssertTrue(wrap.waitForExistence(timeout: 5))
        let hammerCard = button(beginningWith: "Hammerlock,")   // the card, not the "Hammerlock exit" row
        XCTAssertTrue(hammerCard.waitForExistence(timeout: 3))
        wrap.press(forDuration: 0.4, thenDragTo: hammerCard, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.staticTexts["Moved to Hammerlock"].waitForExistence(timeout: 3), "drop shows the Undo toast")
        XCTAssertTrue(waitForCount(of: "In Hammerlock", toBe: 2), "dropped clip gains its tag")
        snap("08-drag-moved")
        app.buttons["Undo"].tap()
        XCTAssertTrue(waitForCount(of: "In Hammerlock", toBe: 1), "Undo puts the clip back with its video")

        // Move via long-press menu. Opening a context menu on a `.draggable` row keeps the app "animating"
        // for XCUITest, so the next two steps each wait out the 60s idle timeout. The menu itself works.
        XCTAssertTrue(wrap.waitForExistence(timeout: 5))
        wrap.press(forDuration: 1.0)
        app.buttons["Move"].tap()
        let footwork = app.buttons["Footwork"].firstMatch
        XCTAssertTrue(footwork.waitForExistence(timeout: 3))
        footwork.tap()
        snap("09-move-sheet")
        app.buttons["Move to Footwork"].tap()
        sleep(2)
        snap("09b-after-move")
        XCTAssertTrue(app.staticTexts["In Footwork"].waitForExistence(timeout: 3))
    }

    /// Hovering a subfolder card for 0.9s opens it with the clip still in hand; releasing files it there.
    func testSpringLoadedDrop() throws {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting", "-seedDemo"]
        app.launch()
        let turns = button(beginningWith: "Turns")
        guard turns.waitForExistence(timeout: 10) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }
        turns.tap()
        app.openClipDecks()
        let wrap = button(beginningWith: "Wrap and unwrap")
        XCTAssertTrue(wrap.waitForExistence(timeout: 5))
        let hammerCard = button(beginningWith: "Hammerlock,")
        wrap.press(forDuration: 0.4, thenDragTo: hammerCard, withVelocity: .slow, thenHoldForDuration: 1.6)
        XCTAssertTrue(app.staticTexts["Moved to Hammerlock"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Hammerlock"].exists, "the hovered folder opened")
        XCTAssertTrue(button(beginningWith: "Wrap and unwrap").exists, "the clip is now a loose clip here")
        snap("11-spring-loaded")
    }

    func testHomeReorderByDrag() throws {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting", "-seedDemo"]
        app.launch()
        let turns = button(beginningWith: "Turns")
        let footwork = button(beginningWith: "Footwork")
        guard turns.waitForExistence(timeout: 10) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }
        XCTAssertLessThan(turns.frame.minX, footwork.frame.minX, "seed puts Turns first")
        footwork.press(forDuration: 0.8, thenDragTo: turns, withVelocity: .slow, thenHoldForDuration: 0.5)
        snap("10-home-reordered")
        let moved = NSPredicate { _, _ in footwork.frame.minX < turns.frame.minX }
        wait(for: [expectation(for: moved, evaluatedWith: nil)], timeout: 3)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "folders")).firstMatch.exists,
                      "subtitle is back to the clip count once the drag ends")
    }

    private func button(beginningWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func waitForLabel(of element: XCUIElement, toBe label: String, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate { _, _ in element.label == label }
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: nil)], timeout: timeout) == .completed
    }

    private func waitForLabel(of element: XCUIElement, toDifferFrom label: String, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate { _, _ in element.exists && element.label != label }
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: nil)], timeout: timeout) == .completed
    }

        private func waitForCount(of label: String, toBe count: Int, timeout: TimeInterval = 3) -> Bool {
        let query = app.staticTexts.matching(identifier: label)
        let predicate = NSPredicate { _, _ in query.count == count }
        return XCTWaiter().wait(for: [expectation(for: predicate, evaluatedWith: nil)], timeout: timeout) == .completed
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
