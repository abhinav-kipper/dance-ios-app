/// Hold the right third of the video to step forward frame by frame, the left third to step back (Player).
public enum HoldSeek {
    public enum Zone: Equatable, Sendable { case rewind, none, forward }

    public static let minimumHold = 0.35
    /// One frame every 0.1s while held: about ⅓ speed for 30fps video, slow enough to study a move.
    public static let frameInterval = 0.1

    public static func zone(forX x: Double, width: Double) -> Zone {
        guard width > 0, x.isFinite else { return .none }
        let third = width / 3
        if x < third { return .rewind }
        if x > width - third { return .forward }
        return .none
    }

    /// Frames to step per tick: +1 forward, −1 back, 0 in the middle.
    public static func frameStep(for zone: Zone) -> Int {
        switch zone {
        case .forward: 1
        case .rewind: -1
        case .none: 0
        }
    }
}
