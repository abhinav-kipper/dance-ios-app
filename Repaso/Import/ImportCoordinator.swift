import SwiftUI
import PhotosUI
import SwiftData
import RepasoCore

/// Copies picked videos into the library one at a time, so progress is honest and the disk isn't thrashed.
/// Lives for the whole app session, so hiding the import sheet doesn't stop the import.
@Observable @MainActor
final class ImportCoordinator {
    struct Item: Identifiable {
        enum State: Equatable {
            case waiting
            case copying(Double)
            case done
            case failed(String)
        }

        let id = UUID()
        let pick: PhotosPickerItem
        var name: String
        var state: State = .waiting
        var poster: ThumbnailRequest?
        var duration: Double?
        var size: Int64?
    }

    private(set) var items: [Item] = []
    private var target: Folder?
    private var runner: Task<Void, Never>?

    var isRunning: Bool { runner != nil }

    var overallProgress: Double {
        guard !items.isEmpty else { return 0 }
        let sum = items.reduce(0.0) { acc, item in
            switch item.state {
            case .done, .failed: acc + 1
            case .copying(let p): acc + p
            case .waiting: acc
            }
        }
        return sum / Double(items.count)
    }

    func start(_ picks: [PhotosPickerItem], into folder: Folder?, context: ModelContext, env: AppEnvironment) {
        guard !picks.isEmpty else { return }
        if !isRunning { items.removeAll() }
        target = folder
        let offset = items.count
        items += picks.enumerated().map { Item(pick: $1, name: "Video \(offset + $0 + 1)") }
        run(context: context, env: env)
    }

    func retry(_ id: UUID, context: ModelContext, env: AppEnvironment) {
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
        let pick = items[index].pick
        func update(_ change: (inout Item) -> Void) {
            if let j = items.firstIndex(where: { $0.id == id }) { change(&items[j]) }
        }

        update { $0.state = .copying(0.05) }
        do {
            guard let transfer = try await pick.loadTransferable(type: VideoTransfer.self) else {
                throw ImportError.unreadable
            }
            update { $0.state = .copying(0.7) }
            let meta = try await VideoMetadata.load(transfer.url)
            let fileName = try env.videos.adopt(fileAt: transfer.url)
            let original = try env.library(context).addOriginal(
                title: Self.title(recordedAt: meta.recordedAt, fallback: "Imported video"),
                fileName: fileName, duration: meta.duration, recordedAt: meta.recordedAt, to: target)
            update {
                $0.name = original.title
                $0.duration = meta.duration
                $0.size = env.videos.fileSize(fileName)
                $0.poster = original.thumbnailRequest
                $0.state = .done
            }
            _ = await env.thumbnails.image(for: original.thumbnailRequest)
        } catch {
            update { $0.state = .failed(Self.message(for: error)) }
        }
    }

    /// Photos hands over temp file names, so titles come from the recording date.
    static func title(recordedAt: Date?, fallback: String) -> String {
        guard let recordedAt else { return fallback }
        return recordedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + " class"
    }

    static func message(for error: Error) -> String {
        if (error as NSError).code == NSFileWriteOutOfSpaceError { return "Not enough space" }
        return "Couldn't import this video"
    }

    enum ImportError: Error { case unreadable }
}
