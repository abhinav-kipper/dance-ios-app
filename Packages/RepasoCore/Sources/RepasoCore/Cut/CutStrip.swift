import Foundation

/// Geometry of Cut's scrolling filmstrip: the whole video lies along a strip that scrolls under a fixed playhead
/// in the middle. The strip is padded by half its visible width on both sides, so content offset `x` puts
/// time `x / pointsPerSecond` under the playhead.
public enum CutStrip {
    /// Seconds across the strip when Cut opens.
    public static let defaultVisible = 30.0
    public static let minVisible = 8.0
    public static let maxVisible = 300.0
    /// Thumbnail tiles cover one of these spans, picked so a tile is at least `tileTargetWidth` wide.
    public static let tileSpans: [Double] = [0.5, 1, 2, 3, 5, 10, 15, 30, 60, 120, 300]
    public static let tileTargetWidth = 44.0

    /// Zoom limits for a video: never wider than the whole video (or 5 minutes), never below 8s.
    public static func clampVisible(_ seconds: Double, duration: Double) -> Double {
        let upper = max(minVisible, min(maxVisible, duration))
        guard seconds.isFinite else { return min(defaultVisible, upper) }
        return min(max(seconds, minVisible), upper)
    }

    public static func pointsPerSecond(visible: Double, width: Double) -> Double {
        guard visible > 0, width > 0 else { return 1 }
        return width / visible
    }

    /// Scroll offset that puts `time` under the playhead.
    public static func offset(for time: Double, pointsPerSecond pps: Double, duration: Double) -> Double {
        min(max(0, time), max(0, duration)) * pps
    }

    /// Time under the playhead at scroll offset `x`.
    public static func time(forOffset x: Double, pointsPerSecond pps: Double, duration: Double) -> Double {
        guard pps > 0, x.isFinite else { return 0 }
        return min(max(0, x / pps), max(0, duration))
    }

    /// Total strip width: the video plus half a screen of padding at each end.
    public static func contentWidth(duration: Double, pointsPerSecond pps: Double, visibleWidth: Double) -> Double {
        max(0, duration) * pps + visibleWidth
    }

    public static func tileSpan(pointsPerSecond pps: Double) -> Double {
        tileSpans.first { $0 * pps >= tileTargetWidth } ?? tileSpans[tileSpans.count - 1]
    }

    public static func tileCount(duration: Double, span: Double) -> Int {
        guard duration > 0, span > 0 else { return 0 }
        return Int((duration / span).rounded(.up))
    }
}
