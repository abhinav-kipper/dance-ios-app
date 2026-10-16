import XCTest

extension XCUIApplication {
    /// Clips start collapsed in a deck under each video; opens every deck on screen ("Show N clips").
    @MainActor
    func openClipDecks(timeout: TimeInterval = 5) {
        let decks = buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND (label ENDSWITH %@ OR label ENDSWITH %@)",
                                                 "Show ", " clips", " clip"))
        _ = decks.firstMatch.waitForExistence(timeout: timeout)
        while decks.firstMatch.exists {
            decks.firstMatch.tap()
        }
    }
}

extension XCUIApplication {
    /// The Player's panel slides down to its grabber while playing; brings it (and the top bar) back.
    @MainActor
    func showPlayerControls() {
        let show = buttons["Show controls"]
        if show.exists && show.isHittable { show.tap() }
    }
}
