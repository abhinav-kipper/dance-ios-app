import XCTest

/// Deleting a full video can keep its clips: each is saved as its own short video and still plays.
/// Needs `seed.mov` in the app's Documents folder (see DemoSeed); skipped otherwise.
@MainActor
final class KeepClipsTests: XCTestCase {
    private let app = XCUIApplication()

    func testDeleteFullVideoButKeepItsClips() throws {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting", "-seedDemo", "-noLivePreviews"]
        app.launch()
        let videos = button(beginningWith: "Videos")
        guard videos.waitForExistence(timeout: 15) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }

        // Saturday social has one clip, "Basic with styling", filed in Footwork
        videos.tap()
        let saturday = app.staticTexts["Saturday social"]
        XCTAssertTrue(saturday.waitForExistence(timeout: 5))
        saturday.press(forDuration: 1.0)
        app.buttons["Delete video"].tap()
        let keep = app.buttons["Keep the clip, delete the video"]
        XCTAssertTrue(keep.waitForExistence(timeout: 3), "deleting a video with clips offers to keep them")
        snap("24-delete-keep-clips")
        keep.tap()
        XCTAssertTrue(saturday.waitForNonExistence(timeout: 20), "the full video is gone once its clip is saved")
        XCTAssertTrue(app.staticTexts["Thursday class"].exists, "other videos stay")

        // The clip is still in Footwork and still plays
        app.buttons["Back to Home"].firstMatch.tap()
        button(beginningWith: "Footwork").tap()
        let clip = button(beginningWith: "Basic with styling")
        XCTAssertTrue(clip.waitForExistence(timeout: 5), "the kept clip stays where it was filed")
        clip.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 5))
        let video = app.descendants(matching: .any)["Video"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Video file missing"].exists, "it plays from its own file")
        snap("25-kept-clip-plays")
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
