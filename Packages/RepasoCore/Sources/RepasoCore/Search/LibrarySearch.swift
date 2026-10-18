import Foundation

/// Search across the whole library: clips and folders. Case- and accent-insensitive; every word in the
/// query must match one of an item's fields (the start of a word, or anywhere for 3+ letters).
@MainActor
public enum LibrarySearch {
    public struct Results {
        public var clips: [Clip] = []
        public var folders: [Folder] = []
        public var isEmpty: Bool { clips.isEmpty && folders.isEmpty }
    }

    public static let limit = 50

    public static func results(for query: String, clips: [Clip], folders: [Folder]) -> Results {
        let words = Self.words(query)
        guard !words.isEmpty else { return Results() }
        var out = Results()
        out.clips = ranked(clips.filter(\.isFiled), words: words, name: \.name, others: clipFields, newest: \.addedAt)
        out.folders = ranked(folders, words: words, name: \.name,
                             others: { $0.ancestors.map(\.name) }, newest: \.createdAt)
        return out
    }

    // MARK: Fields

    private static func clipFields(_ clip: Clip) -> [String] {
        clip.instructors + [clip.note ?? "", clip.folder?.name ?? ""] + clip.linkedFolders.map(\.name)
    }

    // MARK: Matching

    /// Items whose fields match every word: name matches first, then the newest.
    private static func ranked<T>(_ items: [T], words: [String], name: (T) -> String, others: (T) -> [String],
                                  newest: (T) -> Date) -> [T] {
        let scored: [(item: T, score: Int, date: Date)] = items.compactMap { item in
            let nameField = fold(name(item))
            let otherFields = others(item).map(fold)
            var nameHits = 0
            for word in words {
                if matches(word, in: nameField) {
                    nameHits += 1
                } else if !otherFields.contains(where: { matches(word, in: $0) }) {
                    return nil
                }
            }
            return (item, nameHits == words.count ? 0 : 1, newest(item))
        }
        return scored
            .sorted { ($0.score, $1.date) < ($1.score, $0.date) }
            .prefix(limit)
            .map(\.item)
    }

    static func matches(_ word: String, in field: String) -> Bool {
        if field.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(word) }) {
            return true
        }
        return word.count >= 3 && field.contains(word)
    }

    static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}
