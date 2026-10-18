import SwiftUI
import RepasoCore

/// The guide's progress: a dot per step that applies, the current one a green pill, done ones pink.
struct StepDots: View {
    let steps: [ImportStep]
    let current: ImportStep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let at = steps.firstIndex(of: current) ?? 0
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, _ in
                Capsule()
                    .fill(i == at ? Theme.accent : Theme.rose.opacity(i < at ? 1 : 0.3))
                    .frame(width: i == at ? 22 : 8, height: 8)
            }
        }
        .animation(Theme.motion(reduceMotion), value: current)
        .animation(Theme.motion(reduceMotion), value: steps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(at + 1) of \(steps.count)")
    }
}
