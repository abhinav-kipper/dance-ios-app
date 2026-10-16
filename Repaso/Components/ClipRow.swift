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
    /// "Add to folders…" (also show it in other folders).
    var link: (Clip) -> Void = { _ in }
    /// "Remove from <folder>" for a clip shown here through a link; nil where that doesn't apply.
    var unlink: ((Clip) -> Void)?
    /// The folder being shown, for the "Remove from" label.
    var folderName: String?
}

/// 60pt clip row: poster, name, duration, location tag; favorite, learned and play buttons.
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
        HStack(spacing: 6) {
            Button { actions.play(clip) } label: {
                HStack(spacing: 10) {
                    PosterView(request: clip.thumbnailRequest, cornerRadius: 10, live: clip.previewSource)
                        .frame(width: 64, height: 44)
                        .modifier(DeckMatch(id: clip.id, namespace: deckNamespace))
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
        .frame(minHeight: 64)
        .opacity(isLifted ? 0.28 : 1)
        .scaleEffect(isLifted ? 0.97 : 1)
        .animation(Theme.spring, value: isLifted)
        .modifier(ClipDragSource(clip: clip, drag: env.drag, origin: dragOrigin, isEnabled: isDraggable, reduceMotion: reduceMotion))
        .contextMenu {
            Button("Rename", systemImage: "pencil") { actions.info(clip) }
            Button("Move", systemImage: "folder") { actions.move(clip) }
            Button("Add to folders…", systemImage: "folder.badge.plus") { actions.link(clip) }
            if linkedHome != nil, let unlink = actions.unlink {
                Button("Remove from \(actions.folderName ?? "this folder")", systemImage: "link.badge.plus") { unlink(clip) }
            }
            Button("Share", systemImage: "square.and.arrow.up") { actions.share(clip) }
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

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            Image(systemName: clip.isFavorite ? "star.fill" : "star")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(clip.isFavorite ? Theme.rose : Theme.textSecondary)
                .symbolEffect(.bounce, value: clip.isFavorite)
                .frame(width: 44, height: 44)
                .contentShape([.interaction, .accessibility], Rectangle())
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

    private var isLifted: Bool { env.drag.active?.id == clip.id }

    private func toggleFavorite() {
        env.perform { try env.library(ctx).toggleFavorite(clip) }
    }

    private func toggleLearned() {
        env.perform { try env.library(ctx).toggleLearned(clip) }
    }
}

private struct ClipDragSource: ViewModifier {
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
