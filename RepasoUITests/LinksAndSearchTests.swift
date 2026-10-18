import XCTest

/// A clip can also show in other folders (with a Linked badge), and the library can be searched.
/// Needs `seed.mov` in the app's Documents folder (see DemoSeed); skipped otherwise.
@MainActor
final class LinksAndSearchTests: XCTestCase {
    private let app = XCUIApplication()

    func testAddToFoldersThenSearch() throws {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting", "-seedDemo", "-noLivePreviews"]
        app.launch()
        let turns = button(beginningWith: "Turns")
        guard turns.waitForExistence(timeout: 15) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }

        // Add "Double turn prep" to Footwork as well
        turns.tap()
        let prep = button(beginningWith: "Double turn prep")
        XCTAssertTrue(prep.waitForExistence(timeout: 5))
        prep.press(forDuration: 1.0)
        app.buttons["Add to folders…"].tap()
        let footworkRow = app.buttons["Footwork"].firstMatch
        XCTAssertTrue(footworkRow.waitForExistence(timeout: 3))
        footworkRow.tap()
        snap("12-link-sheet")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Also in 1 folder"].firstMatch.waitForExistence(timeout: 3))

        // It shows in Footwork with the Linked badge
        app.buttons["Back to Home"].firstMatch.tap()
        button(beginningWith: "Footwork").tap()
        let linked = button(beginningWith: "Double turn prep")
        XCTAssertTrue(linked.waitForExistence(timeout: 5), "linked clip shows in Footwork")
        XCTAssertTrue(app.descendants(matching: .any)["Linked here; home is Turns"].firstMatch.exists, "with the Linked badge")
        snap("13-linked-in-footwork")

        // Remove it from Footwork only
        linked.press(forDuration: 1.0)
        app.buttons["Remove from Footwork"].tap()
        XCTAssertTrue(linked.waitForNonExistence(timeout: 3), "removed from Footwork")

        // Search by clip name, then by folder
        app.buttons["Back to Home"].firstMatch.tap()
        app.buttons["Search"].firstMatch.tap()
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("hammer")
        XCTAssertTrue(button(beginningWith: "Hammerlock exit").waitForExistence(timeout: 3), "finds the clip by name")
        snap("14-search")
        app.buttons["Clear search"].tap()
        field.typeText("footwork")
        XCTAssertTrue(app.buttons["Open Footwork"].waitForExistence(timeout: 3), "finds the folder")
        app.buttons["Open Footwork"].tap()
        XCTAssertTrue(app.staticTexts["Footwork"].firstMatch.waitForExistence(timeout: 3))
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
