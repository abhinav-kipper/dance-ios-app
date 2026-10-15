import XCTest

final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateFolderFromEmptyState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Import your first class video"].waitForExistence(timeout: 5))
        app.buttons["New folder"].tap()

        let field = app.textFields["Folder name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Turns\n")

        XCTAssertTrue(app.staticTexts["Turns"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Favorites"].exists)
    }
}
