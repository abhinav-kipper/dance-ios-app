import XCTest

/// The whole Favorites tile opens it; in the Player's panel the star toggles favorite and the More menu moves and deletes.
/// Needs `seed.mov` in the app's Documents folder (see DemoSeed); skipped otherwise.
@MainActor
final class PlayerActionsTests: XCTestCase {
    private let app = XCUIApplication()

    func testFavoritesTilePanelButtonsAndMoreMenu() throws {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting", "-seedDemo", "-noLivePreviews"]
        app.launch()
        let turns = button(beginningWith: "Turns")
        guard turns.waitForExistence(timeout: 15) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }

        // Tapping the tile away from its text opens Favorites
        let tile = button(beginningWith: "Favorites")
        XCTAssertTrue(tile.exists)
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.15)).tap()
        let backHome = app.buttons["Back to Home"].firstMatch
        XCTAssertTrue(backHome.waitForExistence(timeout: 3), "the whole Favorites tile is tappable")
        backHome.tap()

        // Rows have no play button any more; tapping the row plays
        turns.tap()
        let prep = button(beginningWith: "Double turn prep")
        XCTAssertTrue(prep.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Play clip"].exists, "rows no longer carry a play button")
        prep.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 5))

        // Panel: favorite flips (paused first, so the panel doesn't slide away mid-step)
        app.descendants(matching: .any)["Video"].firstMatch.tap()
        app.showPlayerControls()
        let favorite = app.buttons["Add to favorites"].firstMatch
        XCTAssertTrue(favorite.waitForExistence(timeout: 3), "the panel shows the favorite button")
        snap("18-player-panel-buttons")
        favorite.tap()
        XCTAssertTrue(app.buttons["Remove from favorites"].firstMatch.waitForExistence(timeout: 3))

        // More menu: Folders… opens from the Player
        let more = app.buttons["More actions"]
        more.tap()
        snap("19-player-more-menu")
        XCTAssertFalse(app.buttons["Name & note…"].exists, "renaming is a tap on the name; notes have their own button")
        app.buttons["Folders…"].tap()
        XCTAssertTrue(app.staticTexts["Folders"].waitForExistence(timeout: 3), "Folders opens from the Player")
        app.swipeDown(velocity: .fast)   // close the sheet
        XCTAssertTrue(app.staticTexts["Folders"].waitForNonExistence(timeout: 3))

        // More menu: delete closes the Player and removes the clip
        more.tap()
        app.buttons["Delete clip"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Delete clip")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForNonExistence(timeout: 4), "deleting closes the Player")
        XCTAssertTrue(prep.waitForNonExistence(timeout: 4), "and the clip is gone from the folder")
    }

    /// A swipe from the left edge closes the Player, like going back anywhere else.
    func testEdgeSwipeClosesPlayer() throws {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting", "-seedDemo", "-noLivePreviews"]
        app.launch()
        let turns = button(beginningWith: "Turns")
        guard turns.waitForExistence(timeout: 15) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }
        turns.tap()
        let prep = button(beginningWith: "Double turn prep")
        XCTAssertTrue(prep.waitForExistence(timeout: 5))
        prep.tap()
        let close = app.buttons["Close player"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.45))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45)),
                   withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(close.waitForNonExistence(timeout: 4), "the edge swipe closes the Player")
        XCTAssertTrue(prep.exists, "back on the folder")
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
