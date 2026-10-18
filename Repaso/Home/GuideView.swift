import SwiftUI

/// How-to cards: shown once on first launch, and any time from the ? button on Home.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    struct Card: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let lines: [String]
    }

    static let cards: [Card] = [
        Card(id: 0, symbol: "square.and.arrow.down", title: "Bring in your class videos", lines: [
            "Tap Import and pick videos from Photos, screen recordings included.",
            "Tag the teacher and the class. With several videos, tap ✎ on one to give it its own.",
            "When it's done, Go to takes you to where they landed.",
        ]),
        Card(id: 1, symbol: "scissors", title: "Cut the moves you want", lines: [
            "Tap Cut on a video, then Mark start and Mark end around a move.",
            "Scroll the strip to move through the video; pinch it to see more.",
            "Select a clip and drag its handles to trim. Pull the video down to close.",
        ]),
        Card(id: 2, symbol: "figure.dance", title: "Practise frame by frame", lines: [
            "Tap the middle to play or pause.",
            "Tap the left or right side for one frame back or forward; hold it to keep stepping.",
            "Swipe up or down for the next clip. Pinch to zoom; two-finger tap to reset.",
        ]),
        Card(id: 3, symbol: "slider.horizontal.below.rectangle", title: "Your controls", lines: [
            "While playing, the panel slides away. Drag its handle up to bring it back.",
            "Slow it down, loop it, and add a pause before each repeat.",
            "★ favourite, ✓ learned, and ••• to rename, add a note, move, share or delete.",
        ]),
        Card(id: 4, symbol: "folder", title: "Keep it organised", lines: [
            "Press and hold any video, clip or folder for its menu.",
            "Drag a clip onto a folder to file it. Add to folders shows it in several at once.",
            "Make a New folder right from any folder picker.",
        ]),
        Card(id: 5, symbol: "magnifyingglass", title: "Find your way", lines: [
            "Swipe right to go back. Hold Back to jump straight Home.",
            "Search clips, teachers, classes, notes and folders from Home.",
            "Open this guide again any time with ? on Home.",
        ]),
    ]

    private var isLast: Bool { page == Self.cards.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .opacity(isLast ? 0 : 1)
                    .accessibilityHidden(isLast)
            }
            .padding(.horizontal, Theme.gutter)

            TabView(selection: $page) {
                ForEach(Self.cards) { card in
                    cardView(card).tag(card.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(Theme.motion(reduceMotion), value: page)

            dots
                .padding(.bottom, 20)
            Button {
                if isLast { dismiss() } else { withAnimation(Theme.motion(reduceMotion)) { page += 1 } }
            } label: {
                Text(isLast ? "Start practising" : "Next")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func cardView(_ card: Card) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)
            Image(systemName: card.symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(tint(card))
                .frame(width: 84, height: 84)
                .background(tint(card).opacity(0.15), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .accessibilityHidden(true)
            Text(card.title)
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(card.lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(tint(card)).frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(line)
                            .font(.system(size: 17))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.gutter + 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Cards alternate green and pink, like the app: green for doing, pink for finding your way.
    private func tint(_ card: Card) -> Color { card.id.isMultiple(of: 2) ? Theme.accent : Theme.rose }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(Self.cards) { card in
                Capsule()
                    .fill(card.id == page ? Theme.accent : .white.opacity(0.25))
                    .frame(width: card.id == page ? 22 : 8, height: 8)
            }
        }
        .animation(Theme.motion(reduceMotion), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(Self.cards.count)")
    }
}
