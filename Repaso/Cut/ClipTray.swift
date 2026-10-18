import SwiftUI
import RepasoCore

/// Horizontal cards for the clips of the video being cut, newest first.
struct ClipTray: View {
    @Bindable var model: CutModel
    let clips: [Clip]
    @Binding var renameRequest: UUID?
    let onRename: (Clip, String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renamingID: UUID?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        // No header or empty-state text: the tray simply appears once there's a clip to show.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(clips) { clip in
                    card(clip)
                        .transition(reduceMotion ? .opacity
                            : .offset(y: 40).combined(with: .scale(scale: 0.6)).combined(with: .opacity))
                }
            }
            .padding(.horizontal, Theme.gutter)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring, value: clips.map(\.id))
        }
        .opacity(clips.isEmpty ? 0 : 1)
        .frame(height: clips.isEmpty ? 0 : nil)
        .accessibilityLabel("Clips")
        .onChange(of: renameRequest) { _, id in
            guard let id, let clip = clips.first(where: { $0.id == id }) else { return }
            renameRequest = nil
            if model.selectedID != id { select(clip) }
            draft = ""   // empty: typing replaces the name; return with nothing keeps it
            renamingID = id
            focused = true
        }
    }

    private func card(_ clip: Clip) -> some View {
        let selected = clip.id == model.selectedID
        return VStack(alignment: .leading, spacing: 4) {
            if renamingID == clip.id {
                TextField(clip.name, text: $draft)   // the current name shows as the hint
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { commit(clip) }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit(clip) } }
                    .accessibilityLabel("Clip name")
                    .accessibilityIdentifier("Clip name")
            } else {
                HStack(spacing: 5) {
                    Text(clip.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "pencil")   // names are tappable to rename
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                    // 44pt tap target without growing the card: the extra height overlaps its padding.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 13)
                    .contentShape([.interaction, .accessibility], Rectangle())
                    .padding(.vertical, -13)
                    .onTapGesture {
                        // Tapping a name always renames (and selects the card if it wasn't).
                        if !selected { select(clip) }
                        draft = ""   // empty: typing replaces the name; return with nothing keeps it
                        renamingID = clip.id
                        focused = true
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Renames the clip")
            }
            Text("\(TimeFormat.range(clip.start))–\(TimeFormat.range(clip.end))")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
            Text(TimeFormat.length(clip.length))
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(selected ? Theme.accent : .white.opacity(0.75))
                .accessibilityLabel(String(format: "%.1f seconds", clip.length))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 156, alignment: .leading)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selected ? Theme.accent : .white.opacity(0.18), lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture { select(clip) }
        .animation(Theme.spring, value: selected)
    }

    private func select(_ clip: Clip) {
        if model.selectedID == clip.id {
            model.selectedID = nil
        } else {
            model.selectedID = clip.id
            model.seek(clip.start)
        }
    }

    private func commit(_ clip: Clip) {
        guard renamingID == clip.id else { return }
        renamingID = nil
        onRename(clip, draft)
    }
}
