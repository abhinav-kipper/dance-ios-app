import Foundation
import SwiftData

@Model
public final class Folder {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var sortIndex: Int
    public var createdAt: Date
    public var parent: Folder?
    @Relationship(deleteRule: .nullify, inverse: \Folder.parent) public var children: [Folder] = []
    /// Clips that live here.
    @Relationship(deleteRule: .nullify, inverse: \Clip.folder) public var clips: [Clip] = []
    /// Clips whose home is elsewhere but are also shown here.
    public var linkedClips: [Clip] = []
    /// The folder clips land in when their top-level folder is deleted.
    public var isOrphans: Bool = false

    public init(name: String, sortIndex: Int, parent: Folder? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.sortIndex = sortIndex
        self.parent = parent
        self.createdAt = createdAt
    }

    /// Root first, excluding self.
    public var ancestors: [Folder] {
        var chain: [Folder] = []
        var cursor = parent
        while let f = cursor {
            chain.insert(f, at: 0)
            cursor = f.parent
        }
        return chain
    }

    public func isDescendant(of other: Folder) -> Bool {
        ancestors.contains { $0.id == other.id }
    }
}
