import SwiftUI
import SwiftData
import RepasoCore

/// Actions a clip row can ask its screen to present.
struct ClipActions {
    var play: (Clip) -> Void
    var move: (Clip) -> Void
    var info: (Clip) -> Void
    var delete: (Clip) -> Void
}

/// 60pt clip row: poster, name, duration, location tag; favorite, learned and play buttons.
struct ClipRow: View {
    enum Context { case underOriginal, loose }

    let clip: Clip
    let context: Context
    let actions: ClipActions
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var ctx

    var body: some View {
        HStack(spacing: 6) {
            Button { actions.play(clip) } label: {
                HStack(spacing: 10) {
                    PosterView(request: clip.thumbnailRequest, cornerRadius: 8)
                        .frame(width: 46, height: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(clip.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        meta
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(clip.name), \(TimeFormat.duration(clip.length))")
            .accessibilityHint("Plays the clip")

            // Touching 44pt targets, no gaps: leaves room for the name and location tag.
            HStack(spacing: 0) {
                favoriteButton
                learnedButton
                playButton
            }
        }
        .frame(minHeight: 60)
        .contextMenu {
            Button("Rename or add note", systemImage: "pencil") { actions.info(clip) }
            Button("Move", systemImage: "folder") { actions.move(clip) }
            Button(clip.isFavorite ? "Remove from favorites" : "Add to favorites", systemImage: "star") { toggleFavorite() }
            Button(clip.isLearned ? "Mark as not learned" : "Mark as learned", systemImage: "checkmark") { toggleLearned() }
            Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(clip) }
        }
    }

    @ViewBuilder
    private var meta: some View {
        HStack(spacing: 8) {
            Text(TimeFormat.duration(clip.length))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()   // never wrap the timecode; the tag truncates instead
            switch context {
            case .underOriginal:
                if clip.isFiledElsewhere, let folder = clip.folder {
                    Text("In \(folder.name)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.accentTint, in: Capsule())
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            case .loose:
                if let title = clip.original?.title {
                    Text("from \(title)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            Image(systemName: clip.isFavorite ? "star.fill" : "star")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(clip.isFavorite ? Theme.rose : Theme.textSecondary)
                .symbolEffect(.bounce, value: clip.isFavorite)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(clip.isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private var learnedButton: some View {
        Button(action: toggleLearned) {
            ZStack {
                if clip.isLearned {
                    Circle().fill(Theme.accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                } else {
                    Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1.5)
                }
            }
            .frame(width: 26, height: 26)
            .symbolEffect(.bounce, value: clip.isLearned)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(clip.isLearned ? "Mark as not learned" : "Mark as learned")
    }

    private var playButton: some View {
        Button { actions.play(clip) } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.15), in: Circle())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Play clip")
    }

    private func toggleFavorite() {
        env.perform { try env.library(ctx).toggleFavorite(clip) }
    }

    private func toggleLearned() {
        env.perform { try env.library(ctx).toggleLearned(clip) }
    }
}
