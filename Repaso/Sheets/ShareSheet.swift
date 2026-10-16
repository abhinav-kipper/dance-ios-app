import SwiftUI
import UIKit
import RepasoCore

/// Exports just the clip's range, then hands the file to the system share sheet.
struct ShareSheet: View {
    let clip: Clip
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var progress = 0.0
    @State private var file: URL?
    @State private var failure: String?
    @State private var attempt = 0

    /// Temporary exports live here; emptied before each export and at launch.
    static var exportsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    static func clearExports() {
        try? FileManager.default.removeItem(at: exportsDirectory)
    }

    var body: some View {
        VStack(spacing: 18) {
            PosterView(request: clip.thumbnailRequest, cornerRadius: 12)
                .frame(width: 120, height: 80)
                .overlay(alignment: .bottomTrailing) {
                    Text(TimeFormat.duration(clip.length))
                        .font(Theme.mono(10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(4)
                }
                .padding(.top, 28)
            Text(clip.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            if let failure {
                Text(failure)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.rose)
                PrimarySheetButton(title: "Try again") {
                    self.failure = nil
                    attempt += 1
                }
            } else {
                VStack(spacing: 10) {
                    Text(file == nil ? "Exporting \(Int(progress * 100))%" : "Ready to share")
                        .font(Theme.mono(15))
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.numericText())
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule().fill(Theme.accent).frame(width: geo.size.width * progress)
                            }
                        }
                        .animation(.easeOut(duration: 0.2), value: progress)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet(detents: [.medium])
        .task(id: attempt) { await export() }
        .sheet(isPresented: Binding(get: { file != nil }, set: { if !$0 { file = nil; dismiss() } })) {
            if let file {
                ActivityView(items: [file]) { dismiss() }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func export() async {
        guard let original = clip.original else { return }
        let source = env.videos.url(for: original.fileName)
        guard FileManager.default.fileExists(atPath: source.path) else {
            failure = "Video file missing"
            return
        }
        Self.clearExports()
        let dir = Self.exportsDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let destination = dir.appendingPathComponent(ClipExport.fileName(for: clip.name))
            let range = ClipExport.timeRange(start: clip.start, end: clip.end, duration: original.duration)
            let (updates, sink) = AsyncStream.makeStream(of: Double.self)
            let job = Task.detached(priority: .userInitiated) {
                defer { sink.finish() }
                try await ClipExporter.export(source: source, range: range, to: destination) { sink.yield($0) }
            }
            try await withTaskCancellationHandler {
                for await value in updates { progress = value }
                try await job.value
            } onCancel: {
                job.cancel()
            }
            progress = 1
            file = destination
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { failure = "Couldn't export this clip" }
        }
    }
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
