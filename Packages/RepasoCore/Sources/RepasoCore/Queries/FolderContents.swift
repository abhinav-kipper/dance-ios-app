import Foundation
import SwiftData

/// Read-side rules: what appears where, in what order, and how it is counted.
@MainActor
public enum FolderContents {
    public static func rootFolders(_ ctx: ModelContext) throws -> [Folder] {
        try ctx.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.parent == nil },
                                              sortBy: [SortDescriptor(\.sortIndex)]))
    }

    public static func subfolders(of folder: Folder) -> [Folder] {
        folder.children.sorted { $0.sortIndex < $1.sortIndex }
    }

    public static func unsortedOriginals(_ ctx: ModelContext) throws -> [Original] {
        let all = try ctx.fetch(FetchDescriptor<Original>(predicate: #Predicate { $0.folder == nil }))
        return sortOriginals(all, by: .manual)
    }

    public static func originals(in folder: Folder, sort: ClipSort) -> [Original] {
        sortOriginals(folder.originals, by: sort)
    }

    /// Clips filed in `folder` whose original lives elsewhere.
    public static func looseClips(in folder: Folder, sort: ClipSort, hideLearned: Bool) -> [Clip] {
        let loose = folder.looseClips.filter { $0.original != nil && $0.original?.folder?.id != folder.id }
        return sortClips(filter(loose, hideLearned: hideLearned), by: sort)
    }

    /// All clips of an original, wherever they are filed.
    public static func clips(of original: Original, sort: ClipSort, hideLearned: Bool) -> [Clip] {
        sortClips(filter(original.clips, hideLearned: hideLearned), by: sort)
    }

    public static func favorites(_ ctx: ModelContext, sort: ClipSort) throws -> [Clip] {
        let favs = try ctx.fetch(FetchDescriptor<Clip>(predicate: #Predicate { $0.isFavorite }))
        return sortClips(favs.filter { $0.original != nil }, by: sort)
    }

    /// Player queue for a folder: each original's clips in order, then the loose clips.
    public static func playQueue(originals: [Original], loose: [Clip], sort: ClipSort, hideLearned: Bool) -> [Clip] {
        originals.flatMap { clips(of: $0, sort: sort, hideLearned: hideLearned) } + loose
    }

    /// Clips listed anywhere inside `folder` (recursively), each counted once.
    public static func clipCount(in folder: Folder) -> Int {
        var ids = Set<UUID>()
        collectClipIDs(folder, into: &ids)
        return ids.count
    }

    private static func collectClipIDs(_ folder: Folder, into ids: inout Set<UUID>) {
        for o in folder.originals { o.clips.forEach { ids.insert($0.id) } }
        folder.looseClips.forEach { ids.insert($0.id) }
        folder.children.forEach { collectClipIDs($0, into: &ids) }
    }

    /// Up to `limit` posters: clips first (newest first), then originals, recursing into subfolders.
    public static func mosaic(for folder: Folder, limit: Int = 4) -> [ThumbnailRequest] {
        var out: [ThumbnailRequest] = []
        var queue: [Folder] = [folder]
        while !queue.isEmpty, out.count < limit {
            let f = queue.removeFirst()
            let clips = (f.originals.flatMap(\.clips) + f.looseClips).sorted { $0.addedAt > $1.addedAt }
            out += clips.compactMap(\.thumbnailRequest)
            out += f.originals.map(\.thumbnailRequest)
            queue += subfolders(of: f)
        }
        var seen = Set<UUID>()
        return Array(out.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    public static func totals(_ ctx: ModelContext) throws -> (clips: Int, folders: Int) {
        (try ctx.fetchCount(FetchDescriptor<Clip>()), try ctx.fetchCount(FetchDescriptor<Folder>()))
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

    public static func sortOriginals(_ originals: [Original], by sort: ClipSort) -> [Original] {
        switch sort {
        case .name:
            originals.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        default:
            originals.sorted { ($0.recordedAt ?? $0.importedAt) > ($1.recordedAt ?? $1.importedAt) }
        }
    }
}
