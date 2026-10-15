import Foundation

/// Mark start/end state and filmstrip geometry for Cut mode.
public struct CutSession: Equatable, Sendable {
    public static let maxWindow = 40.0

    public let duration: Double
    public private(set) var markStart: Double?

    public init(duration: Double) { self.duration = duration }

    public var isRecording: Bool { markStart != nil }

    /// First call starts recording and returns nil; second returns the finished range.
    public mutating func mark(at t: Double) -> ClosedRange<Double>? {
        guard let start = markStart else {
            markStart = min(max(0, t), duration)
            return nil
        }
        markStart = nil
        return ClipRange.normalized(start: start, end: t, duration: duration)
    }

    public mutating func cancelMark() { markStart = nil }

    /// Display length while recording, rounded to 0.1s.
    public func liveLength(at t: Double) -> Double? {
        guard let start = markStart else { return nil }
        return (abs(t - start) * 10).rounded() / 10
    }

    // MARK: Filmstrip geometry

    public static func windowLength(for duration: Double) -> Double { min(maxWindow, max(0, duration)) }

    public static func windowStart(center: Double, duration: Double) -> Double {
        let w = windowLength(for: duration)
        return max(0, min(duration - w, center - w / 2))
    }

    public static func x(for time: Double, windowStart: Double, windowLength: Double, width: Double) -> Double {
        guard windowLength > 0 else { return 0 }
        return (time - windowStart) / windowLength * width
    }

    public static func time(forX x: Double, windowStart: Double, windowLength: Double, width: Double) -> Double {
        guard width > 0 else { return windowStart }
        return windowStart + x / width * windowLength
    }

    public static func trimStart(_ range: ClosedRange<Double>, to t: Double) -> ClosedRange<Double> {
        let start = min(max(0, t), range.upperBound - ClipRange.minLength)
        return max(0, start)...range.upperBound
    }

    public static func trimEnd(_ range: ClosedRange<Double>, to t: Double, duration: Double) -> ClosedRange<Double> {
        let end = max(min(duration, t), range.lowerBound + ClipRange.minLength)
        return range.lowerBound...min(end, duration)
    }
}
