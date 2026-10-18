import SwiftUI
import SwiftData
import RepasoCore

/// Actions a clip row can ask its screen to present.
struct ClipActions {
    var play: (Clip) -> Void
    var move: (Clip) -> Void
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
    /// Plays the clip's whole video (not offered for a clip whose full video was deleted).
    var playFull: (Clip) -> Void = { _ in }
    /// Turns on Arrange mode, where clips can be dragged onto folders; nil where there's nothing to drag to.
    var arrange: (() -> Void)?
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
        if clip.original?.isClipSource == false {
            Button("Play full video", systemImage: "film") { actions.playFull(clip) }
        }
        Divider()
        Button("Folders…", systemImage: "folder") { actions.link(clip) }
        if linkedHome != nil, let unlink = actions.unlink {
            Button("Remove from \(actions.folderName ?? "this folder")", systemImage: "link.badge.plus") { unlink(clip) }
        }
        if let arrange = actions.arrange {
            Button("Drag to folders", systemImage: "hand.draw") { arrange() }
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

/// Clip row: poster, name (up to two lines), duration, location tag and small favorite/learned marks.
/// Tapping anywhere plays; favorite, learned and everything else live in the long-press menu and the Player.
struct ClipRow: View {
    enum Context { case underOriginal, loose }

    let clip: Clip
    let context: Context
    let actions: ClipActions
    /// Folder screens let clips be dragged onto subfolders; `dragOrigin` is that screen's folder.
    var isDraggable = false
    var dragOrigin: UUID?
    /// Set for the first rows under a video, so their posters fly out of its deck.
    var deckNamespace: Namespace.ID?
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
                    .modifier(DeckMatch(id: clip.id, namespace: deckNamespace))
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
        .opacity(isLifted ? 0.28 : 1)
        .scaleEffect(isLifted ? 0.97 : 1)
        .animation(Theme.spring, value: isLifted)
        .modifier(ClipDragSource(clip: clip, drag: env.drag, origin: dragOrigin, isEnabled: isDraggable, reduceMotion: reduceMotion))
        .modifier(MenuUnlessArranging(isArranging: isDraggable) {
            ClipMenuItems(clip: clip, actions: actions, linkedHome: linkedHome)
        })
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
                if let linkedHome {
                    LinkBadge(home: linkedHome)
                } else if let title = clip.original?.title {
                    Text("from \(title)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var accessibilityText: String {
        var parts = [clip.name, TimeFormat.duration(clip.length)]
        if clip.isFavorite { parts.append("favorite") }
        if clip.isLearned { parts.append("learned") }
        return parts.joined(separator: ", ")
    }

    private var isLifted: Bool { env.drag.active?.id == clip.id }
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

struct ClipDragSource: ViewModifier {
    let clip: Clip
    let drag: DragState
    let origin: UUID?
    let isEnabled: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.dragSource(DragRef(kind: .clip, id: clip.id), drag: drag, origin: origin) {
                ClipLiftPreview(name: clip.name, length: clip.length, reduceMotion: reduceMotion)
            }
        } else {
            content
        }
    }
}

/// Pairs a row poster with its card in the video's deck (matched geometry), when there is one.
private struct DeckMatch: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
