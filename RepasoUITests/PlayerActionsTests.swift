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
        app.openClipDecks()
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

        // More menu: move opens the Move sheet
        let more = app.buttons["More actions"]
        more.tap()
        snap("19-player-more-menu")
        app.buttons["Move to folder…"].tap()
        XCTAssertTrue(app.staticTexts["Move clip"].waitForExistence(timeout: 3), "Move opens from the Player")
        app.swipeDown(velocity: .fast)   // close the sheet
        XCTAssertTrue(app.staticTexts["Move clip"].waitForNonExistence(timeout: 3))

        // More menu: delete closes the Player and removes the clip
        more.tap()
        app.buttons["Delete clip"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Delete clip")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForNonExistence(timeout: 4), "deleting closes the Player")
        XCTAssertTrue(prep.waitForNonExistence(timeout: 4), "and the clip is gone from the folder")
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
