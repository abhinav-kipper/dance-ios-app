import XCTest

/// Scrolls a 240-clip folder and measures hitches (handoff acceptance: grids scroll smoothly with 200+ clips).
/// Needs `seed.mov` in the app's Documents folder (see DemoSeed); skipped otherwise.
@MainActor
final class ScrollPerformanceTests: XCTestCase {
    func testLargeFolderScrollsSmoothly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-seedDemo", "-seedLarge"]
        app.launch()
        let practice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Practice")).firstMatch
        guard practice.waitForExistence(timeout: 30) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }
        practice.tap()
        app.openClipDecks()
        let list = app.scrollViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            list.swipeUp(velocity: .fast)
            stopMeasuring()
            list.swipeDown(velocity: .fast)   // reset outside the measured window
        }
    }
}
