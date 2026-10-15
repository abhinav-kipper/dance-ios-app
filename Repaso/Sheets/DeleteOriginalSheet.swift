import SwiftUI
import SwiftData
import RepasoCore

/// Confirms deleting a video and all of its clips.
struct DeleteOriginalSheet: View {
    let original: Original
    var onDeleted: (() -> Void)?
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

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
            Text(clips.isEmpty ? "It has no clips." : clips.count == 1 ? "Its 1 clip will be deleted too." : "Its \(clips.count) clips will be deleted too.")
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
            PrimarySheetButton(title: clips.isEmpty ? "Delete video" : "Delete video and \(clips.count) clip\(clips.count == 1 ? "" : "s")",
                               role: .destructive) {
                env.perform { try env.library(ctx).deleteOriginal(original) }
                dismiss()
                onDeleted?()
            }
            Button("Cancel") { dismiss() }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, Theme.gutter)
        .repasoSheet()
    }
}
