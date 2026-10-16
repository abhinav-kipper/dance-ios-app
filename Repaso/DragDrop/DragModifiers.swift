import SwiftUI

extension View {
    /// Makes this view draggable as `ref`. Lifting registers a pending drag in `drag`; on iOS 27+ the session
    /// also reports when it really starts and ends (iOS 26 relies on `DragState.setTargeted`).
    func dragSource<P: View>(_ ref: DragRef, drag: DragState, origin: UUID?, @ViewBuilder preview: () -> P) -> some View {
        modifier(DragSourceModifier(ref: ref, drag: drag, origin: origin, preview: preview()))
    }

    /// Accepts Repaso drags. `perform` returns whether the drop was used; the drag ends either way.
    func dragTarget(_ drag: DragState, isTargeted: @escaping @MainActor (Bool) -> Void = { _ in },
                    perform: @escaping @MainActor (DragRef) -> Bool) -> some View {
        dropDestination(for: DragRef.self) { items, _ in
            MainActor.assumeIsolated {
                let handled = items.first.map(perform) ?? false
                drag.end()
                return handled
            }
        } isTargeted: { targeted in
            MainActor.assumeIsolated {
                drag.setTargeted(targeted)
                isTargeted(targeted)
            }
        }
    }

    /// iOS-style jiggle (±0.8° every 0.32s) for cards while another card is being dragged.
    func jiggle(_ isActive: Bool) -> some View { modifier(Jiggle(isActive: isActive)) }
}

private struct DragSourceModifier<P: View>: ViewModifier {
    let ref: DragRef
    let drag: DragState
    let origin: UUID?
    let preview: P

    func body(content: Content) -> some View {
        let lifted = content.draggable(payload()) { preview }
        if #available(iOS 27, *) {
            lifted.onDragSessionUpdated { session in
                MainActor.assumeIsolated {
                    switch session.phase {
                    case .initial, .active: drag.activate()
                    case .ended: drag.end()
                    default: break
                    }
                }
            }
        } else {
            lifted
        }
    }

    /// Runs when the system lifts the view (for a drag or just a context menu).
    private func payload() -> DragRef {
        let (drag, ref, origin) = (drag, ref, origin)
        MainActor.assumeIsolated { drag.lift(ref, from: origin) }
        return ref
    }
}

private struct Jiggle: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Double.random(in: 0..<(2 * .pi))   // cards shouldn't sway in sync

    func body(content: Content) -> some View {
        let running = isActive && !reduceMotion
        TimelineView(.animation(paused: !running)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            content.rotationEffect(.degrees(running ? sin(t / 0.32 * 2 * .pi + phase) * 0.8 : 0))
        }
    }
}
