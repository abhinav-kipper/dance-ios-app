import Foundation

/// Autocomplete chips for the name card, drawn from clips already made.
@MainActor
public enum TagSuggestions {
    public static func instructors(for query: String, excluding: [String] = [], in clips: [Clip], limit: Int = 3) -> [String] {
        rank(clips.flatMap { c in c.instructors.map { ($0, c.addedAt) } }, query: query, excluding: excluding, limit: limit)
    }

    /// Clip names already used, for the name card.
    public static func names(for query: String, in clips: [Clip], limit: Int = 3) -> [String] {
        rank(clips.map { ($0.name, $0.addedAt) }, query: query, excluding: [], limit: limit)
    }

    /// Most used first, then most recent, then alphabetical. A query keeps prefix matches (whole value or any word)
    /// ahead of other substring matches.
    static func rank(_ uses: [(String, Date)], query: String, excluding: [String], limit: Int) -> [String] {
        struct Stat { var value: String; var count: Int; var last: Date }
        var stats: [String: Stat] = [:]
        for (raw, date) in uses {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let key = value.lowercased()
            if var stat = stats[key] {
                stat.count += 1
                // The newest spelling wins; on a tie, the same one every time.
                if date > stat.last || (date == stat.last && value < stat.value) { stat.value = value }
                stat.last = max(stat.last, date)
                stats[key] = stat
            } else {
                stats[key] = Stat(value: value, count: 1, last: date)
            }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let excluded = Set(excluding.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } + [q])
        let ranked = stats.filter { !excluded.contains($0.key) }.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.last != $1.last { return $0.last > $1.last }
            return $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending
        }
        guard !q.isEmpty else { return ranked.prefix(limit).map(\.value) }
        func isPrefix(_ value: String) -> Bool {
            let lower = value.lowercased()
            return lower.hasPrefix(q) || lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(q) }
        }
        let prefix = ranked.filter { isPrefix($0.value) }
        let substring = ranked.filter { !isPrefix($0.value) && $0.value.lowercased().contains(q) }
        return (prefix + substring).prefix(limit).map(\.value)
    }
}
