import SwiftUI
import RepasoCore

/// A 3-column subfolder card that is also a drop target for clips: pulses while a clip is up, lifts on hover,
/// and "absorbs" when a clip lands on it.
struct SubfolderDropCard: View {
    let folder: Folder
    @Binding var isEditingName: Bool
    let isClipDragActive: Bool
    let isHovered: Bool
    let absorbCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        FolderCard(folder: folder, compact: true, isEditingName: $isEditingName)
            .overlay {
                if isHovered { shape.fill(Theme.roseTint).allowsHitTesting(false) }
            }
            .overlay {
                if isHovered {
                    shape.strokeBorder(Theme.rose, lineWidth: 1.5).allowsHitTesting(false)
                } else if isClipDragActive {
                    // A TimelineView rather than repeatForever: those can keep running after the drag ends,
                    // and then the app never goes idle.
                    TimelineView(.animation(paused: reduceMotion)) { context in
                        shape.strokeBorder(Theme.rose.opacity(pulseOpacity(at: context.date)), lineWidth: 1.5)
                    }
                    .allowsHitTesting(false)
                }
            }
            .scaleEffect(isHovered && !reduceMotion ? 1.08 : 1)
            .offset(y: isHovered && !reduceMotion ? -4 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring, value: isHovered)
            .keyframeAnimator(initialValue: 1.0, trigger: absorbCount) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(1.1)   // instant jump; a zero-length segment gives the next spring a NaN velocity
                    CubicKeyframe(0.92, duration: 0.21)
                    CubicKeyframe(1.04, duration: 0.21)
                    CubicKeyframe(1, duration: 0.18)
                }
            }
    }

    /// The border breathes between 25% and 60% every 1.2s (a steady 40% under Reduce Motion).
    private func pulseOpacity(at date: Date) -> Double {
        if reduceMotion { return 0.4 }
        return 0.425 + 0.175 * sin(date.timeIntervalSinceReferenceDate / 1.2 * 2 * .pi)
    }
}
