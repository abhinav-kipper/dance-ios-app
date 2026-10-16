import SwiftUI
import SwiftData
import RepasoCore

struct ToastState: Identifiable {
    let id = UUID()
    let text: String
    let undo: (() -> Void)?
}

/// App-lifetime services shared through the SwiftUI environment.
@Observable @MainActor
final class AppEnvironment {
    let videos: VideoStore
    let thumbnails: ThumbnailStore
    let importer = ImportCoordinator()
    let drag = DragState()
    let previews = PreviewCoordinator()
    var toast: ToastState?
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

    func showToast(_ text: String, undo: (() -> Void)? = nil, seconds: Double = 3.8) {
        toast = ToastState(text: text, undo: undo)
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
        let referenced = Set(((try? ctx.fetch(FetchDescriptor<Original>())) ?? []).map(\.fileName))
        let videos = videos
        Task.detached(priority: .background) { videos.sweepOrphans(keeping: referenced) }
    }
}
