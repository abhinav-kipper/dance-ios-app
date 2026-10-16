import Foundation

public enum FolderOrder {
    /// Live reorder: `id` takes `target`'s position (lands after it moving forward, before it moving back).
    public static func moving(_ id: UUID, onto target: UUID, in ids: [UUID]) -> [UUID] {
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return ids }
        var out = ids
        out.remove(at: from)
        out.insert(id, at: to)
        return out
    }
}
