import SwiftUI
import RepasoCore

/// Glass card for one video: header with a playable poster, title, Cut pill and expand chevron. Its clips sit
/// beneath as a deck of stacked previews that springs out into rows when tapped.
struct OriginalCard: View {
    let original: Original
    let clips: [Clip]
    let actions: ClipActions
    let onPlay: () -> Void
    let onCut: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void
    var onLink: () -> Void = {}
    /// Set when the video shows in this folder through a link: the name of its home.
    var linkedHome: String?
    /// "Remove from <folder>" for a linked video.
    var onUnlink: (() -> Void)?
    var folderName: String?
    var isDraggable = false
    var dragOrigin: UUID?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var deckSpace

    /// Collapsed by default; remembered per video for the session.
    private var expanded: Bool { env.expandedOriginals.contains(original.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !clips.isEmpty {
                Divider().overlay(.white.opacity(0.1)).padding(.horizontal, 12)
                if expanded {
                    VStack(spacing: 0) {
                        ForEach(Array(clips.enumerated()), id: \.element.id) { i, clip in
                            ClipRow(clip: clip, context: .underOriginal, actions: actions, isDraggable: isDraggable,
                                    dragOrigin: dragOrigin, deckNamespace: i < ClipDeck.visibleCards ? deckSpace : nil)
                                .padding(.horizontal, 12)
                                .riseIn(i)
                                .transition(.opacity)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    ClipDeck(clips: clips, namespace: deckSpace) { setExpanded(true) }
                        .padding(12)
                        .transition(.opacity)
                }
            }
        }
        .cardGlass(radius: Theme.Radius.listCard)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring, value: clips.map(\.id))
    }

    private func setExpanded(_ on: Bool) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.5, dampingFraction: 0.78)) {
            if on { env.expandedOriginals.insert(original.id) } else { env.expandedOriginals.remove(original.id) }
        }
    }

    /// "Workshop · 3 clips" when the import tagged an event.
    private var meta: String {
        let count = original.clips.count == 1 ? "1 clip" : "\(original.clips.count) clips"
        return original.event.map { "\($0) · \(count)" } ?? count
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                PosterView(request: original.thumbnailRequest, cornerRadius: 12, live: original.previewSource)
                    .frame(width: 88, height: 60)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text(TimeFormat.duration(original.duration))
                            .font(Theme.mono(10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(4)
                    }
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Play whole video")
            VStack(alignment: .leading, spacing: 3) {
                Text(original.title)
                    .layoutPriority(-1)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(meta)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                if let linkedHome { LinkBadge(home: linkedHome) }
            }
            Spacer(minLength: 0)
            Button(action: onCut) {
                Label("Cut", systemImage: "scissors")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()   // never wrap; the title gives way instead
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Theme.accentTint, in: Capsule())
                    .frame(minHeight: 44)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Cut clips from this video")
            if !clips.isEmpty {
                Button {
                    setExpanded(!expanded)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .frame(width: 44, height: 44)
                        .contentShape([.interaction, .accessibility], Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Collapse clips" : "Expand clips")
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Play whole video", systemImage: "play", action: onPlay)
            Button("Move video", systemImage: "folder", action: onMove)
            Button("Add to folders…", systemImage: "folder.badge.plus", action: onLink)
            if linkedHome != nil, let onUnlink {
                Button("Remove from \(folderName ?? "this folder")", systemImage: "link.badge.plus", action: onUnlink)
            }
            Button("Delete video", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

/// Up to three clip previews stacked like a deck, with the clip count. Tapping it opens the clips.
struct ClipDeck: View {
    static let visibleCards = 3
    let clips: [Clip]
    let namespace: Namespace.ID
    let open: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: open) {
            HStack(spacing: 18) {
                ZStack {
                    let shown = Array(clips.prefix(Self.visibleCards))
                    ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { i, clip in
                        PosterView(request: clip.thumbnailRequest, cornerRadius: 12)
                            .frame(width: 96, height: 64)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                            .matchedGeometryEffect(id: clip.id, in: namespace)
                            .rotationEffect(.degrees(reduceMotion ? 0 : Self.tilt(i)))
                            .offset(x: CGFloat(i) * 7, y: CGFloat(i) * -5)
                    }
                }
                .frame(width: 96 + 14, height: 64 + 10, alignment: .bottomLeading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(clips.count == 1 ? "1 clip" : "\(clips.count) clips")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Tap to open")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(clips.count == 1 ? "Show 1 clip" : "Show \(clips.count) clips")
    }

    /// Back cards fan out a little: 0°, +3°, −3°.
    private static func tilt(_ i: Int) -> Double {
        switch i {
        case 1: 3
        case 2: -3
        default: 0
        }
    }
}
