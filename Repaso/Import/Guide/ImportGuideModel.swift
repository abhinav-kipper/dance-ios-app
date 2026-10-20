import Foundation
import SwiftData
import RepasoCore

/// Drives the import guide: a queue of videos (still copying, or already in the library) and the step the current
/// one is at. Library changes go through `LibraryService`; the step order comes from `ImportGuideFlow`.
@Observable @MainActor
final class ImportGuideModel: Identifiable {
    /// One video in the queue: a pick still being copied, or a recording already in the library (Unsorted).
    enum Entry: Equatable {
        case pick(ImportCoordinator.Item.ID)
        case recording(UUID)
    }

    /// Where the current video is: still copying, ready to go through the steps, or failed to copy.
    enum Current {
        case copying(Double, ThumbnailRequest?)
        case ready(Recording)
        case failed(String)
    }

    let id = UUID()
    private let env: AppEnvironment
    private let context: ModelContext
    private(set) var queue: [Entry]
    private(set) var index = 0
    private(set) var step: ImportStep = .trimChoice
    /// "Use the whole video" was chosen for the current video.
    private(set) var usedWholeVideo = false
    /// Instructors of the last clip named in this session, to prefill the next name card.
    private(set) var lastInstructors: [String]
    /// The file step's folder for each clip of the current video.
    private(set) var folderChoices: [UUID: Folder] = [:]
    /// Folders the user picked by hand; the others follow the clip above them.
    private var pickedFolders: [UUID: Folder] = [:]
    /// Where the first clip starts: the folder last used in any import, read when the file step opens.
    private var startFolder: Folder?
    private(set) var isFinishing = false
    private(set) var exportProgress: Double?
    /// The guide has nothing left to show (finished, or Continue later): the view closes.
    private(set) var isClosed = false
    /// What this session filed, for the closing toast and the "Delete from Photos?" offer.
    private(set) var finishedVideos = 0
    private(set) var finishedClips = 0
    private(set) var finishedAssetIDs: [String] = []
    /// Where the first clip filed this session went, for the toast's Go to.
    private(set) var firstFolder: Folder?

    private static let lastFolderKey = "import.lastFolderID"

    /// Makes `folder` the first clip's starting folder (an import started from that folder's screen).
    static func suggest(_ folder: Folder) {
        UserDefaults.standard.set(folder.id.uuidString, forKey: lastFolderKey)
    }

    /// A guide over freshly picked videos (their copies are under way in `ImportCoordinator`).
    init(picks: [ImportCoordinator.Item.ID], env: AppEnvironment, context: ModelContext) {
        self.env = env
        self.context = context
        queue = picks.map(Entry.pick)
        lastInstructors = Self.newestInstructors(context)
    }

    /// A guide over videos already in the library (Unsorted), the first at the step it was left on.
    init(resuming recordings: [Recording], env: AppEnvironment, context: ModelContext) {
        self.env = env
        self.context = context
        queue = recordings.map { .recording($0.id) }
        lastInstructors = Self.newestInstructors(context)
        if let first = recordings.first { enter(first) }
    }

    /// Adds more videos to the end of the queue (shared from another app while the guide is open).
    func append(picks: [ImportCoordinator.Item.ID]) {
        queue += picks.map(Entry.pick)
    }

    // MARK: Where we are

    var position: (index: Int, count: Int) { (index, queue.count) }

    var current: Current {
        guard queue.indices.contains(index) else { return .failed("") }
        switch queue[index] {
        case .recording(let id):
            return recording(id).map(Current.ready) ?? .failed("This video is no longer in your library")
        case .pick(let itemID):
            guard let item = env.importer.item(itemID) else { return .failed("Couldn't import this video") }
            switch item.state {
            case .waiting: return .copying(0, item.poster)
            case .copying(let p): return .copying(p, item.poster)
            case .failed(let message): return .failed(message)
            case .done:
                guard let id = item.recordingID, let r = recording(id) else { return .copying(1, item.poster) }
                return .ready(r)
            }
        }
    }

    var recording: Recording? {
        if case .ready(let r) = current { return r }
        return nil
    }

    var flow: ImportGuideFlow {
        guard let r = recording else { return ImportGuideFlow(clipCount: 0, hasWholeClip: false, keepWholeVideo: nil) }
        return ImportGuideFlow(clipCount: r.clips.count, hasWholeClip: r.clips.contains(where: \.coversWholeRecording),
                               keepWholeVideo: r.keepWholeVideo)
    }

    var visibleSteps: [ImportStep] { flow.visibleSteps(usedWholeVideo: usedWholeVideo) }

    /// The current video's clips, in the order they were made.
    var clips: [Clip] {
        recording.map { FolderContents.sortClips($0.clips, by: .manual) } ?? []
    }

    var canFinish: Bool { !clips.isEmpty && clips.allSatisfy { folderChoices[$0.id] != nil } && !isFinishing }

    // MARK: Steps

    func useWholeVideo(name: String, instructors: [String]) throws {
        guard let r = recording else { return }
        let lib = env.library(context)
        try lib.addWholeClip(to: r, name: name, instructors: instructors)
        try lib.setKeepWholeVideo(r, true)
        lastInstructors = TagText.normalized(instructors)
        usedWholeVideo = true
        go(to: .file)
    }

    func startCutting() { go(to: .cut) }

    @discardableResult
    func saveClip(name: String, instructors: [String], range: ClosedRange<Double>) throws -> Clip? {
        guard let r = recording else { return nil }
        let clip = try env.library(context).addClip(to: r, name: name, instructors: instructors,
                                                    start: range.lowerBound, end: range.upperBound)
        lastInstructors = clip.instructors
        return clip
    }

    func doneCutting() {
        guard !clips.isEmpty, let next = flow.next(after: .cut, usedWholeVideo: false) else { return }
        go(to: next)
    }

    func keepWholeVideo(name: String, instructors: [String]) throws {
        guard let r = recording else { return }
        let lib = env.library(context)
        try lib.addWholeClip(to: r, name: name, instructors: instructors)
        try lib.setKeepWholeVideo(r, true)   // after the clip: a new clip resets the answer
        lastInstructors = TagText.normalized(instructors)
        go(to: .file)
    }

    func dropWholeVideo() throws {
        guard let r = recording else { return }
        try env.library(context).setKeepWholeVideo(r, false)
        go(to: .file)
    }

    /// Sets one clip's folder; clips below it that weren't picked by hand follow it.
    func setFolder(_ folder: Folder, for clipID: UUID) {
        pickedFolders[clipID] = folder
        prefillFolders()
    }

    /// Files every clip, exporting them to their own videos first if the full video goes ("Delete it"), then moves
    /// on to the next video. On failure nothing is filed and the video stays at this step.
    func finish() async throws {
        guard let r = recording, canFinish else { return }
        isFinishing = true
        defer {
            isFinishing = false
            exportProgress = nil
        }
        let lib = env.library(context)
        var files: [LibraryService.OwnFile] = []
        if r.keepWholeVideo == false {
            exportProgress = 0
            files = try await OwnFileExporter.export(lib.clipsNeedingOwnFiles(r), env: env) { [weak self] p in
                self?.exportProgress = p
            }
        }
        let filed = clips
        let folders = folderChoices
        let assetID = r.photosAssetID
        do {
            try lib.finish(r, folders: folders, ownFiles: files)
        } catch {
            OwnFileExporter.discard(files, env: env)
            throw error
        }
        finishedVideos += 1
        finishedClips += filed.count
        if let assetID { finishedAssetIDs.append(assetID) }
        if firstFolder == nil { firstFolder = filed.first.flatMap { folders[$0.id] } }
        if let last = filed.last.flatMap({ folders[$0.id] }) {
            UserDefaults.standard.set(last.id.uuidString, forKey: Self.lastFolderKey)   // where the next import starts
        }
        advance()
    }

    /// Leaves the rest (this video included) in Unsorted; copies carry on in the background.
    func continueLater() { isClosed = true }

    /// Skips a video whose copy failed.
    func skipCurrent() { advance() }

    // MARK: Moving along

    private func advance() {
        index += 1
        usedWholeVideo = false
        folderChoices = [:]
        pickedFolders = [:]
        step = .trimChoice
        guard queue.indices.contains(index) else {
            isClosed = true
            return
        }
        if let r = recording { enter(r) }
    }

    /// Opens a video at the step it was left on (a fresh one starts at the beginning).
    func enter(_ recording: Recording) {
        let flow = ImportGuideFlow(clipCount: recording.clips.count,
                                   hasWholeClip: recording.clips.contains(where: \.coversWholeRecording),
                                   keepWholeVideo: recording.keepWholeVideo)
        usedWholeVideo = flow.usesWholeVideoOnly
        go(to: flow.startStep)
    }

    private func go(to step: ImportStep) {
        if step == .file {
            startFolder = Self.lastUsedFolder(context)
            prefillFolders()
        }
        self.step = step
    }

    /// Each clip's folder: picked by hand, or the one above it, the first being the folder last used in any import.
    private func prefillFolders() {
        folderChoices = ImportGuideFlow.folders(for: clips.map(\.id), picked: pickedFolders, lastUsed: startFolder)
    }

    private func recording(_ id: UUID) -> Recording? {
        try? context.fetch(FetchDescriptor<Recording>(predicate: #Predicate { $0.id == id })).first
    }

    private static func lastUsedFolder(_ context: ModelContext) -> Folder? {
        guard let raw = UserDefaults.standard.string(forKey: lastFolderKey), let id = UUID(uuidString: raw) else { return nil }
        return try? context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.id == id })).first
    }

    private static func newestInstructors(_ context: ModelContext) -> [String] {
        var newest = FetchDescriptor<Clip>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        newest.fetchLimit = 1
        return (try? context.fetch(newest).first?.instructors) ?? []
    }
}
