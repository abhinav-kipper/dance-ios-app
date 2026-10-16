import Foundation

public enum PhotosCleanupText {
    public static func prompt(count: Int) -> String {
        count == 1 ? "Delete this video from Photos?" : "Delete \(count) videos from Photos?"
    }
    public static let detail = "They'll also leave iCloud Photos, so Repaso will have the only copy."
    public static let removed = "Removed from Photos"
    public static let kept = "Kept in Photos"
    public static let failed = "Couldn't remove from Photos"
    public static let needsAccess = "Allow full Photos access in Settings to delete"
}

public enum ImportSummary {
    /// "Recorded Oct 12, 2026", or a span when the batch covers several days.
    public static func recordedLine(_ dates: [Date], calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        if calendar.isDate(first, inSameDayAs: last) {
            var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar)
            style.timeZone = calendar.timeZone
            return "Recorded " + first.formatted(style)
        }
        var style = Date.IntervalFormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        return "Recorded " + (first..<last).formatted(style)
    }
}
