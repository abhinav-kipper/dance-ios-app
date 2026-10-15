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
    @Relationship(deleteRule: .nullify, inverse: \Original.folder) public var originals: [Original] = []
    @Relationship(deleteRule: .nullify, inverse: \Clip.folder) public var looseClips: [Clip] = []

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
