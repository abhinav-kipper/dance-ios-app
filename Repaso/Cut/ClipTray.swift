import SwiftUI
import RepasoCore

/// Horizontal cards for the clips of the video being cut, newest first.
struct ClipTray: View {
    @Bindable var model: CutModel
    let clips: [Clip]
    let onRename: (Clip, String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var renamingID: UUID?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clips").sectionLabelStyle()
                Text("\(clips.count)").font(Theme.mono(13)).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.gutter)
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
            if clips.isEmpty {
                Text("Tap Mark start, then Mark end, to cut your first clip.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.gutter)
            }
        }
    }

    private func card(_ clip: Clip) -> some View {
        let selected = clip.id == model.selectedID
        return VStack(alignment: .leading, spacing: 4) {
            if renamingID == clip.id {
                TextField("Clip name", text: $draft)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { commit(clip) }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit(clip) } }
            } else {
                Text(clip.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .onTapGesture {
                        if selected {
                            draft = clip.name
                            renamingID = clip.id
                            focused = true
                        } else {
                            select(clip)
                        }
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(selected ? "Renames the clip" : "Selects the clip")
            }
            Text("\(TimeFormat.range(clip.start))–\(TimeFormat.range(clip.end))")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.textSecondary)
            Text(TimeFormat.length(clip.length))
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(selected ? Theme.accent : .white.opacity(0.75))
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
