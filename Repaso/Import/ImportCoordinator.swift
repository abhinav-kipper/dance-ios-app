import SwiftUI
import PhotosUI
import SwiftData
import RepasoCore

/// Copies picked videos into the library one at a time, in pick order, so progress is honest and the disk isn't
/// thrashed. Each finished copy becomes a pending recording that the import guide walks through. Lives for the whole
/// app session, so closing the guide (Continue later) doesn't stop the copying.
@Observable @MainActor
final class ImportCoordinator {
    struct Item: Identifiable {
        enum State: Equatable {
            case waiting
            case copying(Double)
            case done
            case failed(String)
        }

        /// A Photos picker pick, or a video handed over by the Share extension (already in our temp directory).
        enum Source {
            case pick(PhotosPickerItem)
            case file(URL)
        }

        let id = UUID()
        let source: Source
        var state: State = .waiting
        var poster: ThumbnailRequest?
        /// Photos asset id, for the delete-from-Photos offer (needs the picker's `photoLibrary: .shared()`).
        var assetID: String?
        var recordingID: UUID?
    }

    private(set) var items: [Item] = []
    private var runner: Task<Void, Never>?

    var isRunning: Bool { runner != nil }

    /// Starts copying `picks` and returns their item ids, in pick order, for the guide's queue.
    @discardableResult
    func start(_ picks: [PhotosPickerItem], context: ModelContext, env: AppEnvironment) -> [Item.ID] {
        guard !picks.isEmpty else { return [] }
        if !isRunning { items.removeAll { $0.state == .done || $0.state.isFailed } }
        return enqueue(picks.map { Item(source: .pick($0), assetID: $0.itemIdentifier) }, context: context, env: env)
    }

    /// Starts importing videos shared from another app (no Photos asset id, so no delete-from-Photos offer).
    @discardableResult
    func start(files: [URL], context: ModelContext, env: AppEnvironment) -> [Item.ID] {
        guard !files.isEmpty else { return [] }
        if !isRunning { items.removeAll { $0.state == .done || $0.state.isFailed } }
        return enqueue(files.map { Item(source: .file($0)) }, context: context, env: env)
    }

    private func enqueue(_ new: [Item], context: ModelContext, env: AppEnvironment) -> [Item.ID] {
        items += new
        run(context: context, env: env)
        return new.map(\.id)
    }

    func item(_ id: Item.ID) -> Item? { items.first { $0.id == id } }

    func retry(_ id: Item.ID, context: ModelContext, env: AppEnvironment) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].state = .waiting
        run(context: context, env: env)
    }

    private func run(context: ModelContext, env: AppEnvironment) {
        guard runner == nil else { return }
        runner = Task { [weak self] in
            while let self, let i = self.items.firstIndex(where: { $0.state == .waiting }) {
                await self.process(at: i, context: context, env: env)
            }
            self?.runner = nil
        }
    }

    private func process(at index: Int, context: ModelContext, env: AppEnvironment) async {
        let id = items[index].id
        let source = items[index].source
        let assetID = items[index].assetID
        func update(_ change: (inout Item) -> Void) {
            if let j = items.firstIndex(where: { $0.id == id }) { change(&items[j]) }
        }

        update { $0.state = .copying(0.05) }
        do {
            let url: URL
            switch source {
            case .pick(let pick):
                guard let transfer = try await pick.loadTransferable(type: VideoTransfer.self) else {
                    throw ImportError.unreadable
                }
                url = transfer.url
            case .file(let file):
                url = file
            }
            update { $0.state = .copying(0.7) }
            let meta = try await VideoMetadata.load(url)
            let fileName = try env.videos.adopt(fileAt: url)
            let recording = try env.library(context).addRecording(fileName: fileName, duration: meta.duration,
                                                                  recordedAt: meta.recordedAt, photosAssetID: assetID)
            update {
                $0.recordingID = recording.id
                $0.poster = recording.thumbnailRequest
                $0.state = .done
            }
            _ = await env.thumbnails.image(for: recording.thumbnailRequest)
        } catch {
            update { $0.state = .failed(Self.message(for: error)) }
        }
    }

    /// Photos hands over temp file names, so titles come from the recording date: "Thursday, Oct 16 class".
    static func title(recordedAt: Date?, fallback: String = "Imported video") -> String {
        guard let recordedAt else { return fallback }
        return recordedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + " class"
    }

    static func message(for error: Error) -> String {
        if (error as NSError).code == NSFileWriteOutOfSpaceError { return "Not enough space" }
        return "Couldn't import this video"
    }

    enum ImportError: Error { case unreadable }
}

extension ImportCoordinator.Item.State {
    var isCopying: Bool {
        if case .copying = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
