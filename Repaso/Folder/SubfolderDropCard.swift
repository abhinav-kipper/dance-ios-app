import SwiftUI
import RepasoCore

/// A 3-column subfolder card that is also a drop target for clips: pulses while a clip is dragged, lifts with a
/// filling spring-load ring on hover, and "absorbs" when a clip lands on it.
struct SubfolderDropCard: View {
    let folder: Folder
    @Binding var isEditingName: Bool
    let isClipDragActive: Bool
    let isHovered: Bool
    let absorbCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring = 0.0

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
            .overlay(alignment: .topTrailing) {
                if isHovered { springRing.padding(6) }
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
            .onChange(of: isHovered) { _, hovered in
                ring = 0
                if hovered { withAnimation(.linear(duration: 0.9)) { ring = 1 } }
            }
    }

    /// The border breathes between 25% and 60% every 1.2s (a steady 40% under Reduce Motion).
    private func pulseOpacity(at date: Date) -> Double {
        if reduceMotion { return 0.4 }
        return 0.425 + 0.175 * sin(date.timeIntervalSinceReferenceDate / 1.2 * 2 * .pi)
    }

    /// Fills over 0.9s; when full, the folder opens with the drag still in hand.
    private var springRing: some View {
        ZStack {
            Circle().fill(.black.opacity(0.55))
            Circle()
                .trim(from: 0, to: ring)
                .stroke(Theme.rose, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.rose)
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}
