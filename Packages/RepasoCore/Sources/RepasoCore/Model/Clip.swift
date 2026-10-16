import Foundation
import SwiftData

@Model
public final class Clip {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var start: Double
    public var end: Double
    public var note: String?
    public var isFavorite: Bool = false
    public var isLearned: Bool = false
    public var lastPlayedAt: Date?
    public var addedAt: Date
    public var sortIndex: Int
    public var zoom: Double = 1
    public var panX: Double = 0
    public var panY: Double = 0
    public var original: Original?
    public var folder: Folder?
    /// Extra folders it also shows in (its home is `effectiveFolder`).
    @Relationship(deleteRule: .nullify, inverse: \Folder.linkedClips) public var linkedFolders: [Folder] = []

    public init(name: String, start: Double, end: Double, sortIndex: Int, original: Original, addedAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.start = start
        self.end = end
        self.sortIndex = sortIndex
        self.original = original
        self.addedAt = addedAt
    }

    public var length: Double { end - start }

    /// True when the clip has been filed in a folder other than its original's.
    public var isFiledElsewhere: Bool {
        guard let folder else { return false }
        return folder.id != original?.folder?.id
    }

    /// Where the clip shows up as filed: its own folder, or its original's when it lives with its video.
    public var effectiveFolder: Folder? { folder ?? original?.folder }

    public var thumbnailRequest: ThumbnailRequest? {
        guard let original else { return nil }
        return ThumbnailRequest(id: id, fileName: original.fileName, time: start + (end - start) * 0.3)
    }
}
