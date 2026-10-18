import XCTest

extension XCUIApplication {
    /// The Player's panel slides down to its grabber while playing; brings it (and the top bar) back.
    @MainActor
    func showPlayerControls() {
        let show = buttons["Show controls"]
        if show.exists && show.isHittable { show.tap() }
    }

    /// Closes the Player. Its top bar fades while playing, so a tap on the video (pause) brings it back first.
    /// (`isHittable` can't be asked while it's faded out.)
    @MainActor
    func closePlayer() {
        let close = buttons["Close player"]
        descendants(matching: .any)["Video"].firstMatch.tap()   // pausing always shows the top bar
        RunLoop.current.run(until: .now.addingTimeInterval(0.7))   // let it fade in
        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()   // one tap, never a retried second one
    }
}
