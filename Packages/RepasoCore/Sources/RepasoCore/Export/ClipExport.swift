import Foundation

public enum ClipExport {
    public static let minimumLength = 0.1

    /// A share-safe "<clip name>.mp4".
    public static func fileName(for clipName: String) -> String {
        let illegal = Set("/\\:?*\"<>|")
        let cleaned = String(clipName.map { illegal.contains($0) ? "-" : $0 })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = String(cleaned.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (base.isEmpty ? "Clip" : base) + ".mp4"
    }

    public static func timeRange(start: Double, end: Double, duration: Double) -> ClosedRange<Double> {
        let lower = min(max(0, start), max(0, duration - minimumLength))
        let upper = min(max(end, lower + minimumLength), max(duration, lower + minimumLength))
        return lower...upper
    }
}
