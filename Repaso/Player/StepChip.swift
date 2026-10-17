import SwiftUI
import RepasoCore

/// A small, see-through readout shown while stepping frames ("‹‹‹ 00:03.4"), kept out of the way so the dancer
/// stays visible. Tiny chevrons ripple in the stepping direction on every frame and rest when you stop.
struct StepChip: View {
    let position: Double
    let length: Double
    /// +1 forward, −1 back, 0 before the first step.
    let direction: Int
    /// Changes on every step; each change plays one ripple.
    let tick: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            if direction < 0 { chevrons(pointing: "chevron.left") }
            Text(TimeFormat.precise(position))
                .font(Theme.mono(11))
                .monospacedDigit()
            if direction > 0 { chevrons(pointing: "chevron.right") }
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(.black.opacity(0.22), in: Capsule())
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%.1f of %.1f seconds", position, length))
    }

    /// Three chevrons; a wave runs through them in the stepping direction (the phase rests at 1).
    private func chevrons(pointing symbol: String) -> some View {
        // The animation closure runs off the main actor, so it gets plain values.
        let still = reduceMotion
        let forward = direction > 0
        return HStack(spacing: -2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .heavy))
                    .keyframeAnimator(initialValue: 1.0, trigger: tick) { view, phase in
                        view.opacity(still ? 0.6 : Self.opacity(index: i, phase: phase, forward: forward))
                    } keyframes: { _ in
                        KeyframeTrack {
                            MoveKeyframe(0.0)   // instant reset; never a zero-length segment before a curve
                            LinearKeyframe(1.0, duration: 0.3)
                        }
                    }
            }
        }
        .accessibilityHidden(true)
    }

    /// Bright where the wave is, dim elsewhere; at rest (phase 1) all chevrons are dim.
    nonisolated private static func opacity(index: Int, phase: Double, forward: Bool) -> Double {
        guard phase < 1 else { return 0.35 }
        let position = forward ? Double(index) : Double(2 - index)
        return max(0.35, 1 - abs(phase * 3 - position) * 0.8)
    }
}
