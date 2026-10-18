import SwiftUI
import RepasoCore

/// A clip as a tall preview card in a folder's grid: live poster, name on a soft gradient, duration, and small
/// favorite / learned marks. Tap plays; press and hold opens the menu, or picks it up while arranging.
struct ClipCard: View {
    let clip: Clip
    let actions: ClipActions
    var isArranging = false
    /// Picked up in Arrange (drawn by `arrangeItem`; the card only stops its live preview).
    var isLifted = false
    /// Set when the clip shows in this folder through a link: the name of where it lives.
    var linkedHome: String?

    var body: some View {
        Button {
            if !isArranging { actions.play(clip) }
        } label: {
            Color.clear
                .aspectRatio(0.8, contentMode: .fit)
                .overlay {
                    PosterView(request: clip.thumbnailRequest, cornerRadius: 0,
                               live: isArranging ? nil : clip.previewSource)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 96)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomLeading) { caption }
                .overlay(alignment: .topTrailing) { marks }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isArranging ? "Hold and drag to move" : "Plays the clip")
        .jiggle(isArranging && !isLifted)
        .modifier(MenuUnlessArranging(isArranging: isArranging) {
            ClipMenuItems(clip: clip, actions: actions, linkedHome: linkedHome)
        })
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clip.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                Text(TimeFormat.duration(clip.length))
                    .font(Theme.mono(12))
                    .foregroundStyle(.white.opacity(0.8))
                if let linkedHome { LinkBadge(home: linkedHome) }
            }
        }
        .padding(10)
        .shadow(color: .black.opacity(0.4), radius: 2)
    }

    @ViewBuilder
    private var marks: some View {
        HStack(spacing: 4) {
            if clip.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.rose)
            }
            if clip.isLearned {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, clip.isFavorite || clip.isLearned ? 7 : 0)
        .frame(height: 22)
        .background(clip.isFavorite || clip.isLearned ? .black.opacity(0.45) : .clear, in: Capsule())
        .padding(8)
    }

    private var accessibilityText: String {
        var parts = [clip.name, TimeFormat.duration(clip.length)]
        if clip.isFavorite { parts.append("favorite") }
        if clip.isLearned { parts.append("learned") }
        return parts.joined(separator: ", ")
    }
}
