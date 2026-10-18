import SwiftUI

/// How-to cards: shown once on first launch, and any time from the ? button on Home.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    struct Card: Identifiable {
        enum Demo { case importing, cut, file, practice, arrange }
        let id: Int
        let demo: Demo
        let title: String
        let caption: String
    }

    static let cards: [Card] = [
        Card(id: 0, demo: .importing, title: "Import", caption: "Bring in your class videos from Photos."),
        Card(id: 1, demo: .cut, title: "Cut a move", caption: "Mark where the move starts and ends, then name it."),
        Card(id: 2, demo: .file, title: "File it", caption: "Choose a folder for each clip."),
        Card(id: 3, demo: .practice, title: "Practice", caption: "Tap either side to step a frame. Swipe up for the next clip."),
        Card(id: 4, demo: .arrange, title: "Arrange", caption: "Tap Arrange, then hold and drag to reorder."),
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
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            demo(card.demo)
                .scaleEffect(1.08)
                .frame(height: 440)
            VStack(spacing: 8) {
                Text(card.title)
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(card.caption)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.gutter)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func demo(_ demo: Card.Demo) -> some View {
        switch demo {
        case .importing: ImportDemo()
        case .cut: CutDemo()
        case .file: FileDemo()
        case .practice: PracticeDemo()
        case .arrange: ArrangeDemo()
        }
    }

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
