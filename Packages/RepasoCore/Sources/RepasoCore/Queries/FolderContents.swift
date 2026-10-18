import Foundation
import SwiftData

/// Read-side rules: what appears where, in what order, and how it is counted. Clips of a pending recording (still in
/// the import guide or Unsorted) appear nowhere.
@MainActor
public enum FolderContents {
    public static func rootFolders(_ ctx: ModelContext) throws -> [Folder] {
        try ctx.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.parent == nil },
                                              sortBy: [SortDescriptor(\.sortIndex)]))
    }

    public static func subfolders(of folder: Folder) -> [Folder] {
        folder.children.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Unsorted: videos still to go through the guide, in the order they were picked.
    public static func pendingRecordings(_ ctx: ModelContext) throws -> [Recording] {
        try ctx.fetch(FetchDescriptor<Recording>(predicate: #Predicate { $0.isPending },
                                                 sortBy: [SortDescriptor(\.sortIndex)]))
    }

    /// True when the clip shows in `folder` because of a link (it lives elsewhere).
    public static func isLinked(_ clip: Clip, in folder: Folder) -> Bool {
        clip.folder?.id != folder.id && clip.linkedFolders.contains { $0.id == folder.id }
    }

    public static func favorites(_ ctx: ModelContext, sort: ClipSort) throws -> [Clip] {
        let favs = try ctx.fetch(FetchDescriptor<Clip>(predicate: #Predicate { $0.isFavorite }))
        return sortClips(favs.filter(\.isFiled), by: sort)
    }

    /// The clips that live in `folder`, as its grid shows them, then clips shown here through a link.
    public static func folderClips(in folder: Folder, sort: ClipSort, hideLearned: Bool) -> [Clip] {
        let home = folder.clips.filter(\.isFiled)
        var seen = Set(home.map(\.id))
        let linked = folder.linkedClips.filter { $0.isFiled && seen.insert($0.id).inserted }
        return ordered(filter(home, hideLearned: hideLearned), by: sort, arranged: true)
            + ordered(filter(linked, hideLearned: hideLearned), by: sort)
    }

    /// Manual order: clips arranged by hand keep their places, below any that arrived since; the rest are grouped by
    /// video (newest video first), then in the order they were cut. `arranged` only for the folder they live in.
    static func ordered(_ clips: [Clip], by sort: ClipSort, arranged: Bool = false) -> [Clip] {
        guard sort == .manual else { return sortClips(clips, by: sort) }
        if arranged {
            let placed = clips.filter { $0.folderOrder != nil }.sorted { ($0.folderOrder ?? 0) < ($1.folderOrder ?? 0) }
            return ordered(clips.filter { $0.folderOrder == nil }, by: sort) + placed
        }
        return clips.sorted { a, b in
            let da = a.recording.map { $0.recordedAt ?? $0.importedAt } ?? .distantPast
            let db = b.recording.map { $0.recordedAt ?? $0.importedAt } ?? .distantPast
            if da != db { return da > db }
            if a.recording?.id != b.recording?.id {
                return (a.recording?.id.uuidString ?? "") < (b.recording?.id.uuidString ?? "")
            }
            return (a.sortIndex, a.addedAt) < (b.sortIndex, b.addedAt)
        }
    }

    /// Clips shown anywhere inside `folder` (recursively), each counted once.
    public static func clipCount(in folder: Folder) -> Int {
        var ids = Set<UUID>()
        collectClipIDs(folder, into: &ids)
        return ids.count
    }

    private static func collectClipIDs(_ folder: Folder, into ids: inout Set<UUID>) {
        folderClips(in: folder, sort: .dateAdded, hideLearned: false).forEach { ids.insert($0.id) }
        folder.children.forEach { collectClipIDs($0, into: &ids) }
    }

    /// Up to `limit` posters, newest clips first, recursing into subfolders.
    public static func mosaic(for folder: Folder, limit: Int = 4) -> [ThumbnailRequest] {
        var out: [ThumbnailRequest] = []
        var queue: [Folder] = [folder]
        while !queue.isEmpty, out.count < limit {
            let f = queue.removeFirst()
            out += folderClips(in: f, sort: .dateAdded, hideLearned: false).compactMap(\.thumbnailRequest)
            queue += subfolders(of: f)
        }
        var seen = Set<UUID>()
        return Array(out.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    public static func totals(_ ctx: ModelContext) throws -> (clips: Int, folders: Int) {
        let clips = try ctx.fetch(FetchDescriptor<Clip>()).filter(\.isFiled).count
        return (clips, try ctx.fetchCount(FetchDescriptor<Folder>()))
    }

    // MARK: Sorting

    static func filter(_ clips: [Clip], hideLearned: Bool) -> [Clip] {
        hideLearned ? clips.filter { !$0.isLearned } : clips
    }

    public static func sortClips(_ clips: [Clip], by sort: ClipSort) -> [Clip] {
        switch sort {
        case .manual:
            clips.sorted { ($0.sortIndex, $0.addedAt) < ($1.sortIndex, $1.addedAt) }
        case .name:
            clips.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateAdded:
            clips.sorted { $0.addedAt > $1.addedAt }
        case .recentlyPlayed:
            clips.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        }
    }
}
