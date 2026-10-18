import SwiftUI
import SwiftData
import PhotosUI
import RepasoCore

struct ToastState: Identifiable {
    let id = UUID()
    let text: String
    let undo: (() -> Void)?
    var actionTitle = "Undo"
}

/// App-lifetime services shared through the SwiftUI environment.
@Observable @MainActor
final class AppEnvironment {
    let videos: VideoStore
    let thumbnails: ThumbnailStore
    let importer = ImportCoordinator()
    let drag = DragState()
    let previews = PreviewCoordinator()
    /// Set by a toast's Open button; Home navigates there.
    var pendingRoute: [Route]?
    var toast: ToastState?
    /// Full-video clips whose other clips are being saved to their own files before it's deleted.
    var deletingClipIDs: Set<UUID> = []
    /// The import guide, while it's open (presented from Home, so it covers every screen).
    var guide: ImportGuideModel?
    private var toastTask: Task<Void, Never>?

    init() throws {
        videos = try VideoStore.appDefault()
        thumbnails = try ThumbnailStore.appDefault(videos: videos)
    }

    func library(_ ctx: ModelContext) -> LibraryService {
        let videos = videos
        let thumbnails = thumbnails
        return LibraryService(context: ctx) { files, ids in
            files.forEach(videos.remove(fileName:))
            Task { await thumbnails.remove(ids: ids) }
        }
    }

    /// Starts copying picked videos and opens the guide on them. From a folder screen, that folder is offered first.
    func startImport(_ picks: [PhotosPickerItem], from folder: Folder?, context: ModelContext) {
        guard !picks.isEmpty else { return }
        if let folder { ImportGuideModel.suggest(folder) }
        let ids = importer.start(picks, context: context, env: self)
        guide = ImportGuideModel(picks: ids, env: self, context: context)
    }

    /// Opens the guide on a video waiting in Unsorted.
    func resume(_ recording: Recording, context: ModelContext) {
        guide = ImportGuideModel(resuming: [recording], env: self, context: context)
    }

    func showToast(_ text: String, actionTitle: String = "Undo", undo: (() -> Void)? = nil, seconds: Double = 3.8) {
        toast = ToastState(text: text, undo: undo, actionTitle: actionTitle)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    /// Runs a library mutation; on failure shows "Couldn't save" (LibraryService already rolled back).
    func perform(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            showToast("Couldn't save", seconds: 2.2)
        }
    }

    func sweepOrphans(_ ctx: ModelContext) {
        let referenced = Set(((try? ctx.fetch(FetchDescriptor<Recording>())) ?? []).map(\.fileName))
        let videos = videos
        Task.detached(priority: .background) { videos.sweepOrphans(keeping: referenced) }
    }
}
