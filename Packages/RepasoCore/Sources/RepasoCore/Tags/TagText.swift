import Foundation

/// Parsing for the name card's instructors field.
public enum TagText {
    /// Trims, drops empties, de-duplicates case-insensitively (first spelling wins).
    public static func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    public static func instructors(from text: String) -> [String] {
        normalized(text.split(separator: ",").map(String.init))
    }

    /// The name being typed: everything after the last comma.
    public static func lastToken(of text: String) -> String {
        let last = text.split(separator: ",", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return last.trimmingCharacters(in: .whitespaces)
    }

    /// Replaces the name being typed with `suggestion` and readies the field for the next one.
    public static func completing(_ text: String, with suggestion: String) -> String {
        var parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.isEmpty { parts = [""] }
        parts[parts.count - 1] = suggestion
        return parts.filter { !$0.isEmpty }.joined(separator: ", ") + ", "
    }
}
