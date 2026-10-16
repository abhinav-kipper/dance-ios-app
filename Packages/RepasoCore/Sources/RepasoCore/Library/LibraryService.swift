import Foundation
import SwiftData
import os

public enum FolderDeleteMode: Sendable { case deleteContents, moveContentsUp }

/// The only place library data is mutated. Every method saves on success and rolls back on failure.
@MainActor
public struct LibraryService {
    public typealias FileCleanup = @MainActor (_ fileNames: [String], _ thumbnailIDs: [UUID]) -> Void
    public static let noteLimit = 140
    public static let defaultFolderName = "New folder"

    public let context: ModelContext
    private let cleanup: FileCleanup?
    private let log = Logger(subsystem: "com.amudgal.repaso", category: "library")

    public init(context: ModelContext, cleanup: FileCleanup? = nil) {
        self.context = context
        self.cleanup = cleanup
    }

    // MARK: Folders

    @discardableResult
    public func createFolder(named name: String, in parent: Folder?) throws -> Folder {
        for sibling in try siblings(of: parent) { sibling.sortIndex += 1 }
        let folder = Folder(name: Self.cleanName(name) ?? Self.defaultFolderName, sortIndex: 0, parent: parent)
        context.insert(folder)
        try save()
        return folder
    }

    public func renameFolder(_ folder: Folder, to name: String) throws {
        folder.name = Self.cleanName(name) ?? folder.name
        try save()
    }

    public func moveFolder(_ folder: Folder, to parent: Folder?) throws {
        if let parent, parent.id == folder.id || parent.isDescendant(of: folder) {
            throw LibraryError.invalidMoveTarget
        }
        folder.sortIndex = (try siblings(of: parent).map(\.sortIndex).max() ?? -1) + 1
        folder.parent = parent
        try save()
    }

    /// Persists a full sibling order (end of a Home reorder drag).
    public func setFolderOrder(_ ordered: [Folder]) throws {
        guard let parentID = ordered.first.map({ $0.parent?.id }) else { return }
        guard ordered.allSatisfy({ $0.parent?.id == parentID }) else { throw LibraryError.invalidMoveTarget }
        for (index, folder) in ordered.enumerated() { folder.sortIndex = index }
        try save()
    }

    public func reorderFolder(_ folder: Folder, by offset: Int) throws {
        let ordered = try siblings(of: folder.parent).sorted { $0.sortIndex < $1.sortIndex }
        guard let i = ordered.firstIndex(where: { $0.id == folder.id }) else { return }
        let j = i + offset
        guard ordered.indices.contains(j) else { return }
        var reordered = ordered
        reordered.swapAt(i, j)
        for (index, f) in reordered.enumerated() { f.sortIndex = index }
        try save()
    }

    public func deleteFolder(_ folder: Folder, mode: FolderDeleteMode) throws {
        switch mode {
        case .deleteContents:
            var files: [String] = []
            var thumbs: [UUID] = []
            collectAndDelete(folder, files: &files, thumbs: &thumbs)
            try save()
            if !files.isEmpty || !thumbs.isEmpty { cleanup?(files, thumbs) }
        case .moveContentsUp:
            let target = folder.parent
            var next = (try siblings(of: target).map(\.sortIndex).max() ?? -1) + 1
            for child in folder.children.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                child.parent = target
                child.sortIndex = next
                next += 1
            }
            let originals = folder.originals
            let loose = folder.looseClips
            for original in originals { original.folder = target }
            for clip in loose { clip.folder = target }
            normaliseClips(in: originals + loose.compactMap(\.original))
            context.delete(folder)
            try save()
        }
    }

    private func collectAndDelete(_ folder: Folder, files: inout [String], thumbs: inout [UUID]) {
        for child in folder.children { collectAndDelete(child, files: &files, thumbs: &thumbs) }
        for original in folder.originals {
            files.append(original.fileName)
            thumbs.append(original.id)
            thumbs.append(contentsOf: original.clips.map(\.id))
            context.delete(original)
        }
        // Skip clips whose original is being deleted in this pass (cascade handles them).
        for clip in folder.looseClips where !(clip.original.map { files.contains($0.fileName) } ?? false) {
            thumbs.append(clip.id)
            context.delete(clip)
        }
        context.delete(folder)
    }

    // MARK: Originals

    @discardableResult
    public func addOriginal(title: String, fileName: String, duration: Double, recordedAt: Date?, to folder: Folder?,
                            instructors: [String] = [], event: String? = nil) throws -> Original {
        let original = Original(title: title, fileName: fileName, duration: duration, recordedAt: recordedAt, folder: folder)
        original.instructors = TagText.normalized(instructors)
        original.event = event.flatMap(Self.cleanName)
        context.insert(original)
        try save()
        return original
    }

    public func moveOriginal(_ original: Original, to folder: Folder?) throws {
        original.folder = folder
        normaliseClips(in: [original])
        try save()
    }

    /// Instructor and event tags for a batch of originals (the import sheet's fields).
    public func setTags(_ originals: [Original], instructors: [String], event: String?) throws {
        let names = TagText.normalized(instructors)
        let cleanEvent = event.flatMap(Self.cleanName)
        for original in originals {
            original.instructors = names
            original.event = cleanEvent
        }
        try save()
    }

    public func deleteOriginal(_ original: Original) throws {
        let file = original.fileName
        let thumbs = [original.id] + original.clips.map(\.id)
        context.delete(original)
        try save()
        cleanup?([file], thumbs)
    }

    // MARK: Clips

    @discardableResult
    public func addClip(to original: Original, start: Double, end: Double) throws -> Clip {
        let range = ClipRange.normalized(start: start, end: end, duration: original.duration)
        let number = original.nextClipNumber
        original.nextClipNumber += 1
        let sortIndex = (original.clips.map(\.sortIndex).max() ?? -1) + 1
        let clip = Clip(name: "Clip \(number)", start: range.lowerBound, end: range.upperBound, sortIndex: sortIndex, original: original)
        context.insert(clip)
        try save()
        return clip
    }

    public func updateRange(_ clip: Clip, start: Double, end: Double) throws {
        let range = ClipRange.normalized(start: start, end: end, duration: clip.original?.duration ?? end)
        clip.start = range.lowerBound
        clip.end = range.upperBound
        try save()
        cleanup?([], [clip.id])   // poster is stale
    }

    public func updateInfo(_ clip: Clip, name: String, note: String) throws {
        clip.name = Self.cleanName(name) ?? clip.name
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        clip.note = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.noteLimit))
        try save()
    }

    /// `folder == nil` files the clip back "with its video".
    public func moveClip(_ clip: Clip, to folder: Folder?) throws {
        clip.folder = folder
        if let original = clip.original { normaliseClips(in: [original]) }
        try save()
    }

    /// Files a clip by drag. nil when it already lives in `folder` (nothing changes).
    public func dropClip(_ clip: Clip, on folder: Folder) throws -> ClipMoveReceipt? {
        guard clip.effectiveFolder?.id != folder.id else { return nil }
        let receipt = ClipMoveReceipt(clip: clip, previousFolder: clip.folder, destination: folder)
        try moveClip(clip, to: folder)
        return receipt
    }

    /// Puts a dropped clip back. A since-deleted previous folder means "with its video".
    public func undo(_ receipt: ClipMoveReceipt) throws {
        guard receipt.clip.modelContext != nil, !receipt.clip.isDeleted else { return }
        let previous = receipt.previousFolder.flatMap { $0.modelContext == nil || $0.isDeleted ? nil : $0 }
        try moveClip(receipt.clip, to: previous)
    }

    /// Remembers the player's zoom and pan for this clip (clamped to what can be shown).
    public func setFraming(_ clip: Clip, _ framing: Framing) throws {
        let f = framing.clamped()
        clip.zoom = f.zoom
        clip.panX = f.panX
        clip.panY = f.panY
        try save()
    }

    public func toggleFavorite(_ clip: Clip) throws {
        clip.isFavorite.toggle()
        try save()
    }

    public func toggleLearned(_ clip: Clip) throws {
        clip.isLearned.toggle()
        try save()
    }

    public func markPlayed(_ clip: Clip, at date: Date = .now) throws {
        clip.lastPlayedAt = date
        try save()
    }

    public func deleteClip(_ clip: Clip) throws {
        let id = clip.id
        context.delete(clip)
        try save()
        cleanup?([], [id])
    }

    // MARK: Helpers

    /// A clip filed in the same folder as its original "lives with its video".
    private func normaliseClips(in originals: [Original]) {
        for original in originals {
            for clip in original.clips where clip.folder != nil && clip.folder?.id == original.folder?.id {
                clip.folder = nil
            }
        }
    }

    private func siblings(of parent: Folder?) throws -> [Folder] {
        if let parent { return parent.children }
        return try context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.parent == nil }))
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            log.error("save failed: \(error.localizedDescription)")
            context.rollback()
            throw error
        }
    }

    static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
