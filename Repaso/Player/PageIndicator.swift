import SwiftUI

/// Right-edge position dots: 4pt wide, the active one 22pt tall and green. Shows a window of 9 for long queues.
struct PageIndicator: View {
    let count: Int
    let index: Int
    private let window = 9

    var body: some View {
        let lower = max(0, min(index - window / 2, count - window))
        let upper = min(count, lower + window)
        VStack(spacing: 6) {
            ForEach(lower..<upper, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.accent : .white.opacity(0.4))
                    .frame(width: 4, height: i == index ? 22 : 4)
            }
        }
        .animation(Theme.spring, value: index)
        .accessibilityHidden(true)   // the top pill already says "i / n"
    }
}
