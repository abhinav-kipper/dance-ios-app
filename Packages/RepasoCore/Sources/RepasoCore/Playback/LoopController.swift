/// What happens when playback reaches the end of a clip: restart, restart after a pause, or stop.
public struct LoopController: Equatable, Sendable {
    public enum Gap: Int, CaseIterable, Sendable {
        case none = 0, one = 1, two = 2

        public var seconds: Double { Double(rawValue) }
        public var label: String { self == .none ? "No pause" : "\(rawValue)s pause" }
        /// Fits the Player's crowded button row: "Off", "1s", "2s".
        public var shortLabel: String { self == .none ? "Off" : "\(rawValue)s" }
    }

    public enum EndAction: Equatable, Sendable { case restart, restartAfter(Double), stop }

    public var loopEnabled = true
    public var gap: Gap = .none

    public init() {}

    public func actionAtEnd() -> EndAction {
        guard loopEnabled else { return .stop }
        return gap == .none ? .restart : .restartAfter(gap.seconds)
    }

    public mutating func cycleGap() {
        gap = Gap(rawValue: (gap.rawValue + 1) % Gap.allCases.count) ?? .none
    }
}
