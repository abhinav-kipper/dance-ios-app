import SwiftUI
import SwiftData
import RepasoCore

/// Deleting a clip. The clip that is a full video, while other clips were cut from it, takes those clips' own files
/// first, so they keep playing.
@MainActor
enum ClipRemover {
    /// Other clips that would need their own file if `clip` (a full video) went.
    static func dependents(of clip: Clip, lib: LibraryService) -> [Clip] {
        guard clip.coversWholeRecording, let recording = clip.recording else { return [] }
        return lib.clipsNeedingOwnFiles(recording)
    }

    static func delete(_ clip: Clip, env: AppEnvironment, ctx: ModelContext) {
        let lib = env.library(ctx)
        let others = dependents(of: clip, lib: lib)
        guard !others.isEmpty else {
            env.perform { try lib.deleteClip(clip) }
            return
        }
        guard env.deletingClipIDs.insert(clip.id).inserted else { return }   // already being deleted
        env.showToast("Saving \(others.count == 1 ? "1 clip" : "\(others.count) clips")…", seconds: 30)
        let id = clip.id
        Task {
            defer { env.deletingClipIDs.remove(id) }
            do {
                let files = try await OwnFileExporter.export(others, env: env)
                guard clip.modelContext != nil, !clip.isDeleted else {   // gone meanwhile (its folder was deleted)
                    OwnFileExporter.discard(files, env: env)
                    return
                }
                do {
                    try lib.deleteWholeClip(clip, siblingsMovedTo: files)
                    env.showToast("Full video deleted", seconds: 2.2)
                } catch {
                    OwnFileExporter.discard(files, env: env)
                    env.showToast("Couldn't save", seconds: 2.2)
                }
            } catch {
                env.showToast("Couldn't delete", seconds: 2.2)
            }
        }
    }
}

/// The "Delete this clip?" confirmation every clip screen shares.
struct ClipDeleteDialog: ViewModifier {
    @Binding var clip: Clip?
    /// Runs before the delete (the Player closes first so the clip isn't on screen).
    var before: (() -> Void)?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var ctx

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: Binding(get: { clip != nil }, set: { if !$0 { clip = nil } }),
                                   titleVisibility: .visible, presenting: clip) { clip in
            Button(othersCount(clip) > 0 ? "Delete full video" : "Delete “\(clip.name)”", role: .destructive) {
                let env = env
                let ctx = ctx
                if let before {
                    before()
                    Task {
                        try? await Task.sleep(for: .seconds(0.5))
                        ClipRemover.delete(clip, env: env, ctx: ctx)
                    }
                } else {
                    ClipRemover.delete(clip, env: env, ctx: ctx)
                }
            }
        } message: { clip in
            let others = othersCount(clip)
            if others > 0 {
                Text("Your \(others == 1 ? "1 other clip stays" : "\(others) other clips stay"). They can only be trimmed shorter later.")
            }
        }
    }

    private var title: String {
        guard let clip, othersCount(clip) > 0 else { return "Delete this clip?" }
        return "Delete the full video?"
    }

    private func othersCount(_ clip: Clip) -> Int {
        ClipRemover.dependents(of: clip, lib: env.library(ctx)).count
    }
}

extension View {
    func clipDeleteDialog(_ clip: Binding<Clip?>, before: (() -> Void)? = nil) -> some View {
        modifier(ClipDeleteDialog(clip: clip, before: before))
    }
}
