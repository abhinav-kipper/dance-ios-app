import XCTest

/// Runs Xcode's accessibility audit on each main screen of a seeded library.
/// Needs `seed.mov` in the app's Documents folder (see DemoSeed); skipped otherwise.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private let app = XCUIApplication()

    func testMainScreensPassAudit() throws {
        app.launchArguments = ["-uiTesting", "-seedDemo", "-noLivePreviews"]
        app.launch()
        let turns = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Turns")).firstMatch
        guard turns.waitForExistence(timeout: 10) else {
            throw XCTSkip("No seed.mov in the app container; DemoSeed did nothing.")
        }
        try audit("Home")

        turns.tap()
        let wrap = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wrap and unwrap")).firstMatch
        XCTAssertTrue(wrap.waitForExistence(timeout: 5))
        try audit("Folder")

        // Cut before the Player: Done closes Cut reliably, while the Player's close button fades with its controls.
        // Trim… opens the cutter with the clip selected (handles on screen too)
        wrap.press(forDuration: 1.0)
        app.buttons["Trim…"].tap()
        XCTAssertTrue(app.buttons["Mark start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Clip start"].firstMatch.waitForExistence(timeout: 3),
                      "the trimmed clip starts selected")
        try audit("Cut")
        app.buttons["Done"].tap()

        XCTAssertTrue(wrap.waitForExistence(timeout: 5))
        wrap.tap()
        XCTAssertTrue(app.buttons["Close player"].waitForExistence(timeout: 5))
        try audit("Player")
    }

    /// Fails on tap areas, missing labels and wrong traits. Records everything else (attached, not failing):
    /// contrast is unreliable over Liquid Glass and video, and while playing the Player dims its chrome on purpose;
    /// "inaccessible text" picks up timecodes drawn inside the sample video; Dynamic Type is a known gap
    /// (fixed font sizes from the design brief).
    private func audit(_ screen: String) throws {
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .trait])

        var found: [String] = []
        try app.performAccessibilityAudit { issue in
            let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' \($0.frame)" } ?? "-"
            found.append("[\(screen)] \(issue.auditType) | \(issue.compactDescription) | \(element)")
            return true
        }
        for line in found { print("AUDIT " + line) }
        let report = XCTAttachment(string: found.joined(separator: "\n"))
        report.name = "audit-\(screen)"
        report.lifetime = .keepAlways
        add(report)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "audit-\(screen)-screen"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
