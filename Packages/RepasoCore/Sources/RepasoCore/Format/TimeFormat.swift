import Foundation

public enum TimeFormat {
    /// `03:41.2` — Cut mode playhead.
    public static func precise(_ t: Double) -> String {
        let tenths = Int((max(0, t) * 10).rounded())
        let minutes = tenths / 600
        let seconds = Double(tenths % 600) / 10
        return String(format: "%02d:%04.1f", minutes, seconds)
    }

    /// `3:21` — clip ranges, filmstrip labels (floors).
    public static func range(_ t: Double) -> String {
        let s = Int(max(0, t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// `0:08` — durations (rounds).
    public static func duration(_ t: Double) -> String {
        let s = Int(max(0, t).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// `4.2s` — clip lengths.
    public static func length(_ t: Double) -> String {
        String(format: "%.1fs", max(0, t))
    }
}
