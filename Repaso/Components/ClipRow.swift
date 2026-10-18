import SwiftUI
import SwiftData
import RepasoCore

/// Actions a clip row can ask its screen to present.
struct ClipActions {
    var play: (Clip) -> Void
    var info: (Clip) -> Void
    var delete: (Clip) -> Void
    var share: (Clip) -> Void
    /// "Folders…": where it lives and where else it shows.
    var link: (Clip) -> Void = { _ in }
    /// "Remove from <folder>" for a clip shown here through a link; nil where that doesn't apply.
    var unlink: ((Clip) -> Void)?
    /// The folder being shown, for the "Remove from" label.
    var folderName: String?
    /// Opens the cutter on the clip's video with the clip selected, to trim it.
    var trim: (Clip) -> Void = { _ in }
}

/// The long-press menu every clip shares (rows, cards).
struct ClipMenuItems: View {
    let clip: Clip
    let actions: ClipActions
    var linkedHome: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var ctx

    var body: some View {
        Button("Name & note…", systemImage: "pencil") { actions.info(clip) }
        Button("Trim…", systemImage: "timeline.selection") { actions.trim(clip) }
        Divider()
        Button("Folders…", systemImage: "folder") { actions.link(clip) }
        if linkedHome != nil, let unlink = actions.unlink {
            Button("Remove from \(actions.folderName ?? "this folder")", systemImage: "link.badge.plus") { unlink(clip) }
        }
        Divider()
        Button("Share", systemImage: "square.and.arrow.up") { actions.share(clip) }
        Button(clip.isFavorite ? "Remove from favorites" : "Add to favorites", systemImage: "star") {
            env.perform { try env.library(ctx).toggleFavorite(clip) }
        }
        Button(clip.isLearned ? "Mark as not learned" : "Mark as learned", systemImage: "checkmark") {
            env.perform { try env.library(ctx).toggleLearned(clip) }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(clip) }
    }
}

/// Clip row: poster, name (up to two lines), duration, where it lives, and small favorite/learned marks.
/// Tapping anywhere plays; favorite, learned and everything else live in the long-press menu and the Player.
struct ClipRow: View {
    let clip: Clip
    let actions: ClipActions
    /// Set when the clip shows in this folder through a link: the name of its home.
    var linkedHome: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var ctx

    var body: some View {
        Button { actions.play(clip) } label: {
            HStack(spacing: 10) {
                PosterView(request: clip.thumbnailRequest, cornerRadius: 10, live: clip.previewSource)
                    .frame(width: 64, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(clip.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    meta
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Plays the clip")
        .frame(minHeight: 64)
        .contextMenu { ClipMenuItems(clip: clip, actions: actions, linkedHome: linkedHome) }
    }

    @ViewBuilder
    private var meta: some View {
        HStack(spacing: 8) {
            if clip.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.rose)
            }
            if clip.isLearned {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            Text(TimeFormat.duration(clip.length))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()   // never wrap the timecode; the tag truncates instead
            if let linkedHome {
                LinkBadge(home: linkedHome)
            } else if let folder = clip.folder {
                Text("in \(folder.name)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var accessibilityText: String {
        var parts = [clip.name, TimeFormat.duration(clip.length)]
        if clip.isFavorite { parts.append("favorite") }
        if clip.isLearned { parts.append("learned") }
        return parts.joined(separator: ", ")
    }
}

/// Press-and-hold means the menu, except in Arrange mode, where it means drag (so the two never clash).
struct MenuUnlessArranging<Items: View>: ViewModifier {
    let isArranging: Bool
    @ViewBuilder let items: () -> Items

    func body(content: Content) -> some View {
        if isArranging {
            content
        } else {
            content.contextMenu { items() }
        }
    }
}
