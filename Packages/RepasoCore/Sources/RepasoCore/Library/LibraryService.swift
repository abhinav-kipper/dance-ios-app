import Foundation
import SwiftData
import os

public enum FolderDeleteMode: Sendable { case deleteContents, moveContentsUp }

/// The only place library data is mutated. Every method saves on success and rolls back on failure.
@MainActor
public struct LibraryService {
    public typealias FileCleanup = @MainActor (_ fileNames: [String], _ thumbnailIDs: [UUID]) -> Void
    /// Notes are a notebook page, not a caption: room for counts, hand placement, how it should feel.
    public static let noteLimit = 1000
    public static let defaultFolderName = "New folder"
    public static let orphansName = "Orphans"

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

    public func deleteFolder(_ folder: Folder, mode: FolderDeleteMode) throws {
        switch mode {
        case .deleteContents:
            var gone = Set<UUID>()
            var thumbs: [UUID] = []
            collectAndDelete(folder, deletedClips: &gone, thumbs: &thumbs)
            let files = dropEmptyRecordings(touchedBy: gone)
            try save()
            if !files.isEmpty || !thumbs.isEmpty { cleanup?(files, thumbs) }
        case .moveContentsUp:
            guard !folder.isOrphans else { throw LibraryError.invalidMoveTarget }
            let target = folder.parent
            // A top-level folder's clips have nowhere above them: they go to Orphans.
            let clipTarget = try target ?? (folder.clips.isEmpty ? nil : orphansFolder(saving: false))
            var next = (try siblings(of: target).map(\.sortIndex).max() ?? -1) + 1
            for child in folder.children.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                child.parent = target
                child.sortIndex = next
                next += 1
            }
            for clip in folder.clips {
                clip.folder = clipTarget
                clip.folderOrder = nil
            }
            // Clips only linked here are linked to the parent instead (root has no links).
            if let target {
                for clip in folder.linkedClips where !clip.linkedFolders.contains(where: { $0.id == target.id }) {
                    clip.linkedFolders.append(target)
                }
            }
            for clip in folder.clips + folder.linkedClips {
                clip.linkedFolders.removeAll { $0.id == clip.folder?.id }
            }
            context.delete(folder)
            try save()
        }
    }

    /// The folder clips land in when their top-level folder is deleted; made on Home (last) the first time.
    @discardableResult
    public func orphansFolder() throws -> Folder {
        try orphansFolder(saving: true)
    }

    private func orphansFolder(saving: Bool) throws -> Folder {
        if let found = try context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.isOrphans })).first {
            return found
        }
        let folder = Folder(name: Self.orphansName, sortIndex: (try siblings(of: nil).map(\.sortIndex).max() ?? -1) + 1)
        folder.isOrphans = true
        context.insert(folder)
        if saving { try save() }
        return folder
    }

    private func collectAndDelete(_ folder: Folder, deletedClips: inout Set<UUID>, thumbs: inout [UUID]) {
        for child in folder.children { collectAndDelete(child, deletedClips: &deletedClips, thumbs: &thumbs) }
        for clip in folder.clips {
            deletedClips.insert(clip.id)
            thumbs.append(clip.id)
            context.delete(clip)
        }
        context.delete(folder)
    }

    /// Deletes filed recordings left with no clips once `deletedClips` are gone; returns their files.
    private func dropEmptyRecordings(touchedBy deletedClips: Set<UUID>) -> [String] {
        let recordings = (try? context.fetch(FetchDescriptor<Recording>(predicate: #Predicate { !$0.isPending }))) ?? []
        var files: [String] = []
        for recording in recordings where recording.clips.contains(where: { deletedClips.contains($0.id) }) {
            guard recording.clips.allSatisfy({ deletedClips.contains($0.id) }) else { continue }
            files.append(recording.fileName)
            context.delete(recording)
        }
        return files
    }

    // MARK: Recordings

    /// A newly imported video: pending, last in Unsorted's order.
    @discardableResult
    public func addRecording(fileName: String, duration: Double, recordedAt: Date?, photosAssetID: String?) throws -> Recording {
        let all = try context.fetch(FetchDescriptor<Recording>())
        let recording = Recording(fileName: fileName, duration: duration, recordedAt: recordedAt,
                                  photosAssetID: photosAssetID, sortIndex: (all.map(\.sortIndex).max() ?? -1) + 1)
        context.insert(recording)
        try save()
        return recording
    }

    // MARK: Clips

    /// A named clip of `recording`. It has no folder until the guide's last step.
    @discardableResult
    public func addClip(to recording: Recording, name: String, instructors: [String], start: Double, end: Double) throws -> Clip {
        guard let cleanName = Self.cleanName(name) else { throw LibraryError.emptyName }
        let range = ClipRange.normalized(start: start, end: end, duration: recording.duration)
        let sortIndex = (recording.clips.map(\.sortIndex).max() ?? -1) + 1
        let clip = Clip(name: cleanName, start: range.lowerBound, end: range.upperBound, sortIndex: sortIndex, recording: recording)
        clip.instructors = TagText.normalized(instructors)
        recording.keepWholeVideo = nil   // a new clip changes what the full video is for: ask again
        context.insert(clip)
        try save()
        return clip
    }

    /// The full video, kept as a clip of its own.
    @discardableResult
    public func addWholeClip(to recording: Recording, name: String, instructors: [String]) throws -> Clip {
        try addClip(to: recording, name: name, instructors: instructors, start: 0, end: recording.duration)
    }

    public func updateRange(_ clip: Clip, start: Double, end: Double) throws {
        let range = ClipRange.normalized(start: start, end: end, duration: clip.recording?.duration ?? end)
        clip.start = range.lowerBound
        clip.end = range.upperBound
        try save()
        cleanup?([], [clip.id])   // poster is stale
    }

    static func cleanNote(_ note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(noteLimit))
    }

    /// A blank name keeps the old one.
    public func updateInfo(_ clip: Clip, name: String, note: String) throws {
        clip.name = Self.cleanName(name) ?? clip.name
        clip.note = Self.cleanNote(note)
        try save()
    }

    public func setInstructors(_ clip: Clip, _ names: [String]) throws {
        clip.instructors = TagText.normalized(names)
        try save()
    }

    public func moveClip(_ clip: Clip, to folder: Folder) throws {
        if clip.folder?.id != folder.id { clip.folderOrder = nil }   // it arrives on top of its new folder
        clip.folder = folder
        clip.linkedFolders.removeAll { $0.id == folder.id }
        try save()
    }

    /// Files a clip by drag. nil when it already lives in `folder` (nothing changes).
    public func dropClip(_ clip: Clip, on folder: Folder) throws -> ClipMoveReceipt? {
        guard clip.folder?.id != folder.id else { return nil }
        let receipt = ClipMoveReceipt(clip: clip, previousFolder: clip.folder, destination: folder)
        try moveClip(clip, to: folder)
        return receipt
    }

    /// Puts a dropped clip back. If its previous folder has since been deleted it stays where it was dropped.
    public func undo(_ receipt: ClipMoveReceipt) throws {
        guard receipt.clip.modelContext != nil, !receipt.clip.isDeleted,
              let previous = receipt.previousFolder, previous.modelContext != nil, !previous.isDeleted else { return }
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

    // MARK: Folders… (one place to say where a clip shows)

    /// The clip shows in exactly `folders`: it keeps living where it is if that's still ticked, otherwise it moves to
    /// the first one, and shows in the rest through links. Nothing ticked: it stays where it lives, with no links.
    public func place(_ clip: Clip, in folders: [Folder]) throws {
        let ids = Set(folders.map(\.id))
        if let first = folders.first, !(clip.folder.map { ids.contains($0.id) } ?? false) {
            clip.folder = first
            clip.folderOrder = nil
        }
        clip.linkedFolders = Self.links(folders, excludingHome: clip.folder)
        try save()
    }

    /// Arrange: the clips living in `folder`, in the order they were dragged into.
    public func setClipOrder(_ clips: [Clip], in folder: Folder) throws {
        guard clips.allSatisfy({ $0.folder?.id == folder.id }) else { throw LibraryError.invalidMoveTarget }
        for (index, clip) in clips.enumerated() { clip.folderOrder = index }
        try save()
    }

    public func setNote(_ clip: Clip, _ note: String) throws {
        clip.note = Self.cleanNote(note)
        try save()
    }

    /// Replaces the folders a clip also shows in. Its home and duplicates are dropped.
    public func setLinks(_ clip: Clip, to folders: [Folder]) throws {
        clip.linkedFolders = Self.links(folders, excludingHome: clip.folder)
        try save()
    }

    public func unlink(_ clip: Clip, from folder: Folder) throws {
        clip.linkedFolders.removeAll { $0.id == folder.id }
        try save()
    }

    static func links(_ folders: [Folder], excludingHome home: Folder?) -> [Folder] {
        var seen = Set<UUID>()
        return folders.filter { $0.id != home?.id && seen.insert($0.id).inserted }
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

    /// Deletes the clip; a filed recording left with no clips goes too, with its file.
    public func deleteClip(_ clip: Clip) throws {
        let id = clip.id
        let files = dropEmptyRecordings(touchedBy: [id])
        context.delete(clip)
        try save()
        cleanup?(files, [id])
    }

    // MARK: Import guide

    /// A clip's own exported video: a file already in the store, `duration` long.
    public struct OwnFile: Sendable, Equatable {
        public let clipID: UUID
        public let fileName: String
        public let duration: Double

        public init(clipID: UUID, fileName: String, duration: Double) {
            self.clipID = clipID
            self.fileName = fileName
            self.duration = duration
        }
    }

    /// The "Keep the full video too?" answer (nil: not asked yet).
    public func setKeepWholeVideo(_ recording: Recording, _ keep: Bool?) throws {
        recording.keepWholeVideo = keep
        try save()
    }

    /// The clips that need their own file before `recording` can go: all but one covering the whole video.
    public func clipsNeedingOwnFiles(_ recording: Recording) -> [Clip] {
        FolderContents.sortClips(recording.clips.filter { !$0.coversWholeRecording }, by: .manual)
    }

    /// The guide's last step: every clip gets its folder and the video leaves Unsorted. With `ownFiles` (the guide's
    /// "Delete it"), those clips move onto their own files in the same save and the full video goes.
    public func finish(_ recording: Recording, folders: [UUID: Folder], ownFiles: [OwnFile] = []) throws {
        guard recording.isPending else { throw LibraryError.notPending }
        guard recording.clips.allSatisfy({ folders[$0.id] != nil }) else { throw LibraryError.missingFolder }
        try checkOwnFiles(ownFiles, on: recording)
        for clip in recording.clips {
            clip.folder = folders[clip.id]
            clip.folderOrder = nil
        }
        recording.isPending = false
        let files = moveToOwnFiles(ownFiles, from: recording)
        try save()
        if !files.isEmpty { cleanup?(files, []) }
    }

    /// Moves each named clip onto its own recording (start 0, the file's length), keeping everything else about it.
    /// The old recording goes once it has no clips left. Nothing changes if any clip isn't on `recording`.
    public func adoptOwnFiles(_ files: [OwnFile], from recording: Recording) throws {
        try checkOwnFiles(files, on: recording)
        let removed = moveToOwnFiles(files, from: recording)
        try save()
        if !removed.isEmpty { cleanup?(removed, []) }
    }

    /// Deletes the clip that is the full video; the other clips of that video move onto `files` first.
    public func deleteWholeClip(_ clip: Clip, siblingsMovedTo files: [OwnFile]) throws {
        guard let recording = clip.recording else { return }
        try checkOwnFiles(files, on: recording)
        let id = clip.id
        context.delete(clip)
        recording.clips.removeAll { $0.id == id }
        let removed = moveToOwnFiles(files, from: recording)
        try save()
        cleanup?(removed, [id])
    }

    /// Deletes a video still in the guide or Unsorted, with the clips made from it so far.
    public func deletePending(_ recording: Recording) throws {
        guard recording.isPending else { throw LibraryError.notPending }
        let file = recording.fileName
        let thumbs = [recording.id] + recording.clips.map(\.id)
        context.delete(recording)
        try save()
        cleanup?([file], thumbs)
    }

    private func checkOwnFiles(_ files: [OwnFile], on recording: Recording) throws {
        let ids = Set(recording.clips.map(\.id))
        guard files.allSatisfy({ ids.contains($0.clipID) }) else { throw LibraryError.unknownClip }
    }

    /// Unsaved. Returns the old file when the recording is left empty and deleted.
    private func moveToOwnFiles(_ files: [OwnFile], from recording: Recording) -> [String] {
        guard !files.isEmpty else { return [] }
        for file in files {
            guard let clip = recording.clips.first(where: { $0.id == file.clipID }) else { continue }
            let own = Recording(fileName: file.fileName, duration: file.duration, recordedAt: recording.recordedAt,
                                photosAssetID: nil, sortIndex: recording.sortIndex, importedAt: recording.importedAt)
            own.isPending = recording.isPending
            context.insert(own)
            clip.recording = own
            clip.start = 0
            clip.end = file.duration
        }
        let moved = Set(files.map(\.clipID))
        recording.clips.removeAll { moved.contains($0.id) }
        guard recording.clips.isEmpty else { return [] }
        context.delete(recording)
        return [recording.fileName]
    }

    // MARK: Helpers

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
