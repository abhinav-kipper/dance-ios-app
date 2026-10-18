import SwiftUI
import SwiftData
import RepasoCore

/// Deletes a video. With clips, it can keep them (each saved as its own short video) or delete them too.
struct DeleteOriginalSheet: View {
    let original: Original
    var onDeleted: (() -> Void)?
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    /// Saving clips as their own videos: (finished, total).
    @State private var keeping: (Int, Int)?

    var body: some View {
        let clips = FolderContents.clips(of: original, sort: .manual, hideLearned: false)
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.rose)
                .frame(width: 64, height: 64)
                .background(Theme.roseTint, in: Circle())
                .padding(.top, 28)
            Text("Delete “\(original.title)”?")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(clips.isEmpty ? "It has no clips."
                 : "Keep its \(clips.count == 1 ? "clip" : "\(clips.count) clips") as short videos of their own, or delete \(clips.count == 1 ? "it" : "them") too.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)

            if !clips.isEmpty {
                VStack(spacing: 8) {
                    ForEach(clips.prefix(4)) { clip in
                        HStack(spacing: 10) {
                            PosterView(request: clip.thumbnailRequest, cornerRadius: 8).frame(width: 46, height: 32)
                            Text(clip.name).font(.system(size: 15)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Spacer()
                            Text(TimeFormat.duration(clip.length)).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    if clips.count > 4 {
                        Text("and \(clips.count - 4) more").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(12)
                .cardGlass(radius: 18)
            }

            Spacer()
            if let keeping {
                VStack(spacing: 10) {
                    ProgressView(value: Double(keeping.0), total: Double(max(keeping.1, 1))).tint(Theme.accent)
                    Text("Saving clip \(min(keeping.0 + 1, keeping.1)) of \(keeping.1)…")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.bottom, 20)
            } else {
                if !clips.isEmpty {
                    PrimarySheetButton(title: clips.count == 1 ? "Keep the clip, delete the video" : "Keep \(clips.count) clips, delete the video") {
                        keepClips(count: clips.count)
                    }
                }
                PrimarySheetButton(title: clips.isEmpty ? "Delete video" : "Delete video and \(clips.count) clip\(clips.count == 1 ? "" : "s")",
                                   role: .destructive) {
                    env.perform { try env.library(ctx).deleteOriginal(original) }
                    dismiss()
                    onDeleted?()
                }
            }
            Button("Cancel") { dismiss() }
                .disabled(keeping != nil)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet()
        .interactiveDismissDisabled(keeping != nil)
    }

    private func keepClips(count: Int) {
        keeping = (0, count)
        let original = original
        let env = env
        let ctx = ctx
        Task {
            do {
                try await ClipKeeper.saveClipsAsOwnVideos(of: original, env: env, context: ctx) { done, total in
                    keeping = (done, total)
                }
                env.perform { try env.library(ctx).deleteOriginal(original) }
                dismiss()
                onDeleted?()
                env.showToast(count == 1 ? "Full video deleted · 1 clip kept" : "Full video deleted · \(count) clips kept")
            } catch {
                keeping = nil
                env.showToast("Couldn't save the clips; the full video is kept", seconds: 3)
            }
        }
    }
}
