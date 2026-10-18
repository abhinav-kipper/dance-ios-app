import XCTest

/// The import guide, from two videos queued by `-seedImport` (the Photos picker can't be driven from UI tests).
/// Needs `seed.mov` in the app's Documents folder (see DemoSeed); skipped otherwise.
@MainActor
final class GuidedImportTests: XCTestCase {
    private let app = XCUIApplication()

    private func launchGuide() throws {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting", "-seedDemo", "-seedImport", "-noLivePreviews"]
        app.launch()
        guard app.buttons["Make clips"].waitForExistence(timeout: 15) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }
    }

    func testUseWholeVideoNameAndFile() throws {
        try launchGuide()
        XCTAssertTrue(app.staticTexts["Video 1 of 2"].exists)
        snap("30-guide-trim-choice")
        app.buttons["Use the whole video"].tap()

        // The name is required: spaces alone can't be saved
        let name = app.textFields["clipName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        app.buttons["Clear Name"].tap()
        name.typeText("   ")
        XCTAssertFalse(app.buttons["saveClip"].isEnabled, "a name of only spaces can't be saved")
        name.typeText("Backazouk")
        snap("31-guide-name-card")
        app.buttons["saveClip"].tap()

        // File it: search for a folder
        let chip = app.buttons["Choose a folder for Backazouk"]
        XCTAssertTrue(chip.waitForExistence(timeout: 3), "the file step lists the clip")
        XCTAssertFalse(app.buttons["Finish"].isEnabled, "every clip needs a folder")
        chip.tap()
        let search = app.textFields["folderSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("foot")
        app.buttons["Footwork"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Folder for Backazouk: Footwork"].waitForExistence(timeout: 3))
        snap("32-guide-file")
        app.buttons["Finish"].tap()

        // On to the second video, then stop there
        XCTAssertTrue(app.staticTexts["Video 2 of 2"].waitForExistence(timeout: 5))
        app.buttons["Continue later"].tap()
        let footwork = button(beginningWith: "Footwork")
        XCTAssertTrue(footwork.waitForExistence(timeout: 5))
        footwork.tap()
        let clip = button(beginningWith: "Backazouk")
        XCTAssertTrue(clip.waitForExistence(timeout: 5), "the clip is filed in Footwork")
        clip.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Video file missing"].exists)
    }

    func testMakeTwoClipsDeleteFullVideoThenFile() throws {
        try launchGuide()
        app.buttons["Make clips"].tap()
        markClip("Turn A")
        markClip("Turn B")
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3), "Done appears once a clip is made")
        done.tap()

        // Keep the full video? Delete it
        XCTAssertTrue(app.staticTexts["Keep the full video too?"].waitForExistence(timeout: 3))
        snap("34-guide-keep")
        app.buttons["Delete it"].tap()

        // File: a new folder from the search, which the next clip then defaults to
        let first = app.buttons["Choose a folder for Turn A"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        first.tap()
        let search = app.textFields["folderSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("Sabado")
        let create = app.buttons["Create “Sabado”"]
        XCTAssertTrue(create.waitForExistence(timeout: 3), "no match offers to create it")
        create.tap()
        XCTAssertTrue(app.buttons["Folder for Turn A: Sabado"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Folder for Turn B: Sabado"].exists, "the next clip starts in the folder above it")
        app.buttons["Finish"].tap()
        XCTAssertTrue(app.staticTexts["Video 2 of 2"].waitForExistence(timeout: 30), "clips saved to their own files")
        app.buttons["Continue later"].tap()

        let sabado = button(beginningWith: "Sabado")
        XCTAssertTrue(sabado.waitForExistence(timeout: 5))
        sabado.tap()
        XCTAssertTrue(button(beginningWith: "Turn B").waitForExistence(timeout: 5))
        button(beginningWith: "Turn A").tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Video file missing"].exists, "it plays from its own file")
    }

    func testContinueLaterThenResume() throws {
        try launchGuide()
        app.buttons["Make clips"].tap()
        markClip("Cross step")
        app.buttons["Continue later"].tap()

        let unsorted = button(beginningWith: "Unsorted · 3")
        XCTAssertTrue(unsorted.waitForExistence(timeout: 5), "Sunday plus both picked videos wait in Unsorted")
        unsorted.tap()
        let started = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "1 clip so far"))
        XCTAssertTrue(started.firstMatch.waitForExistence(timeout: 5))
        snap("35-unsorted")
        started.element(boundBy: started.count - 1).tap()   // the one just left (Sunday is first)
        XCTAssertTrue(app.buttons["Mark start"].waitForExistence(timeout: 5), "it opens back in the cutter")
        XCTAssertTrue(app.buttons["Done"].firstMatch.exists, "with its clip, so Done is there")
    }

    func testDeleteTopLevelFolderSendsClipsToOrphans() throws {
        continueAfterFailure = false
        app.launchArguments = ["-uiTesting", "-seedDemo", "-noLivePreviews"]
        app.launch()
        let footwork = button(beginningWith: "Footwork")
        guard footwork.waitForExistence(timeout: 15) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }
        footwork.press(forDuration: 1.0)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["“Move contents up” keeps its folders on Home. Its clips go to Orphans."]
            .waitForExistence(timeout: 3))
        app.buttons["Move contents up"].tap()
        let orphans = button(beginningWith: "Orphans")
        XCTAssertTrue(orphans.waitForExistence(timeout: 5), "an Orphans folder appears on Home")
        orphans.tap()
        XCTAssertTrue(button(beginningWith: "Basic with styling").waitForExistence(timeout: 5), "holding Footwork's clip")
    }

    /// Mark start, let it play a moment, Mark end, then name the clip.
    private func markClip(_ clipName: String) {
        let start = app.buttons["Mark start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        sleep(2)
        button(beginningWith: "Mark end").tap()   // the label also carries the live length
        let name = app.textFields["clipName"]
        XCTAssertTrue(name.waitForExistence(timeout: 3), "Mark end asks for the clip's name")
        name.typeText(clipName)
        snap("33-guide-name-\(clipName)")
        app.buttons["saveClip"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 3))
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
