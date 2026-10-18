import SwiftUI
import RepasoCore

/// Arrange mode's press-and-drag. A card picked up follows the finger, the others slide into its live order, and
/// letting go over a drop target (a folder card) files it there instead. Built on plain gestures, so it works the
/// same on every iOS version and inside a scroll view (the scroll view is held still while a card is up).
@Observable @MainActor
final class ArrangeSession {
    enum Outcome {
        case reordered([UUID])
        case dropped(UUID, on: UUID)
        case none
    }

    nonisolated static let space = "arrange"

    private(set) var dragging: UUID?
    /// The live order while a card is up; nil otherwise.
    private(set) var order: [UUID]?
    /// The drop target under the finger.
    private(set) var hoveredTarget: UUID?
    private var location: CGPoint = .zero
    /// Where the finger holds the card, from its top-left corner.
    private var grab: CGSize = .zero
    private var startOrder: [UUID] = []
    @ObservationIgnored fileprivate var frames: [UUID: CGRect] = [:]
    @ObservationIgnored fileprivate var targets: [UUID: CGRect] = [:]
    /// Ticks once per reorder step, for a light haptic.
    private(set) var steps = 0

    var isActive: Bool { dragging != nil }

    /// `items` in display order, as shown before the drag.
    func begin(_ id: UUID, at point: CGPoint, items: [UUID]) {
        guard dragging == nil, let frame = frames[id] else { return }
        dragging = id
        startOrder = items
        order = items
        location = point
        grab = CGSize(width: point.x - frame.minX, height: point.y - frame.minY)
    }

    func move(to point: CGPoint) {
        guard let dragging else { return }
        location = point
        if let target = targets.first(where: { $0.key != dragging && $0.value.contains(point) })?.key {
            hoveredTarget = target
            return
        }
        hoveredTarget = nil
        guard let current = order,
              let hit = current.first(where: { $0 != dragging && frames[$0]?.contains(point) == true }) else { return }
        let next = FolderOrder.moving(dragging, onto: hit, in: current)
        if next != current {
            order = next
            steps += 1
        }
    }

    func end() -> Outcome {
        defer {
            dragging = nil
            order = nil
            hoveredTarget = nil
        }
        guard let dragging else { return .none }
        if let target = hoveredTarget { return .dropped(dragging, on: target) }
        if let order, order != startOrder { return .reordered(order) }
        return .none
    }

    /// How far the card under the finger is drawn from its slot.
    func offset(for id: UUID) -> CGSize {
        guard id == dragging, let frame = frames[id] else { return .zero }
        return CGSize(width: location.x - grab.width - frame.minX, height: location.y - grab.height - frame.minY)
    }

    /// `items` in the live order while dragging.
    func arranged<T: Identifiable>(_ items: [T]) -> [T] where T.ID == UUID {
        guard let order else { return items }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { byID[$0] } + items.filter { !order.contains($0.id) }
    }
}

extension View {
    /// A card that can be picked up and moved while `enabled` (Arrange mode). `items` is the order shown now.
    func arrangeItem(_ id: UUID, in session: ArrangeSession, items: [UUID], enabled: Bool,
                     onEnd: @escaping (ArrangeSession.Outcome) -> Void) -> some View {
        modifier(ArrangeItem(id: id, session: session, items: items, enabled: enabled, onEnd: onEnd))
    }

    /// iOS-style jiggle (±0.8° every 0.32s) for cards in Arrange mode.
    func jiggle(_ isActive: Bool) -> some View { modifier(Jiggle(isActive: isActive)) }

    /// Something a card can be dropped on (a folder card).
    func arrangeTarget(_ id: UUID, in session: ArrangeSession) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ArrangeSession.space)) } action: { frame in
            session.targets[id] = frame
        }
    }
}

private struct ArrangeItem: ViewModifier {
    let id: UUID
    let session: ArrangeSession
    let items: [UUID]
    let enabled: Bool
    let onEnd: (ArrangeSession.Outcome) -> Void
    @GestureState private var pressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let lifted = session.dragging == id
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ArrangeSession.space)) } action: { frame in
                session.frames[id] = frame
            }
            .scaleEffect(lifted && !reduceMotion ? 1.06 : 1)
            .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: 18, y: 10)
            .offset(session.offset(for: id))
            .zIndex(lifted ? 10 : 0)
            .animation(Theme.spring, value: lifted)
            .transaction { if lifted && session.isActive { $0.animation = nil } }   // the lifted card sticks to the finger
            .highPriorityGesture(gesture, including: enabled ? .all : .subviews)
            .onChange(of: pressing) { _, isPressing in
                // A gesture the system cancelled never reaches onEnded: settle here instead.
                if !isPressing, session.dragging == id { onEnd(session.end()) }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: lifted) { _, new in new }
            .sensoryFeedback(.selection, trigger: lifted ? session.steps : 0)
    }

    private var gesture: some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(ArrangeSession.space)))
            .updating($pressing) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag?) = value else { return }
                if session.dragging == nil { session.begin(id, at: drag.startLocation, items: items) }
                session.move(to: drag.location)   // the grid animates the reorder (`.animation(value: order)`)
            }
            .onEnded { _ in
                guard session.dragging == id else { return }
                withAnimation(Theme.spring) { onEnd(session.end()) }
            }
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
