import SwiftUI
import RepasoCore

/// Glass card for one video: header with poster, title, Cut pill and expand chevron; its clips beneath.
struct OriginalCard: View {
    let original: Original
    let clips: [Clip]
    let actions: ClipActions
    let onCut: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void
    var isDraggable = false
    var dragOrigin: UUID?
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded && !clips.isEmpty {
                Divider().overlay(.white.opacity(0.1)).padding(.horizontal, 12)
                VStack(spacing: 0) {
                    ForEach(clips) { clip in
                        ClipRow(clip: clip, context: .underOriginal, actions: actions, isDraggable: isDraggable, dragOrigin: dragOrigin)
                            .padding(.horizontal, 12)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .cardGlass(radius: Theme.Radius.listCard)
        .animation(Theme.spring, value: clips.map(\.id))
    }

    /// "Workshop · 3 clips" when the import tagged an event.
    private var meta: String {
        let count = original.clips.count == 1 ? "1 clip" : "\(original.clips.count) clips"
        return original.event.map { "\($0) · \(count)" } ?? count
    }

    private var header: some View {
        HStack(spacing: 12) {
            PosterView(request: original.thumbnailRequest, cornerRadius: 10)
                .frame(width: 64, height: 44)
                .overlay(alignment: .bottomTrailing) {
                    Text(TimeFormat.duration(original.duration))
                        .font(Theme.mono(10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(3)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(original.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(meta)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Button(action: onCut) {
                Label("Cut", systemImage: "scissors")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Theme.accentTint, in: Capsule())
                    .frame(minHeight: 44)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Cut clips from this video")
            Button {
                withAnimation(Theme.spring) { expanded.toggle() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse clips" : "Expand clips")
        }
        .padding(12)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Move video", systemImage: "folder", action: onMove)
            Button("Delete video", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}
