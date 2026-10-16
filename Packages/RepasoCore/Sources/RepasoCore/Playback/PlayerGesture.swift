import Foundation

/// How a one-finger drag on the player video is read (values from the Player prototype).
public enum PlayerGesture {
    public enum Mode: Equatable, Sendable { case pan, swipe, scrub }

    public static let followFactor = 0.55
    public static let commitDistance = 80.0
    public static let slideInDistance = 120.0
    public static let pointsPerFrame = 5.0

    /// nil = not decided yet. Pan wins when zoomed, then a mostly-vertical swipe, then a paused scrub.
    public static func classify(dx: Double, dy: Double, isZoomed: Bool, isPlaying: Bool) -> Mode? {
        if isZoomed && hypot(dx, dy) > 6 { return .pan }
        if abs(dy) > 14 && abs(dy) > abs(dx) { return .swipe }
        if !isPlaying && abs(dx) > 8 { return .scrub }
        return nil
    }

    /// +1 = next clip (swipe up), −1 = previous, 0 = stay.
    public static func swipeDirection(dy: Double) -> Int {
        dy < -commitDistance ? 1 : dy > commitDistance ? -1 : 0
    }

    public static func frames(forDrag dx: Double) -> Int {
        Int((dx / pointsPerFrame).rounded(.towardZero))
    }
}
