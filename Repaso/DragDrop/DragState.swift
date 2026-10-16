import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.amudgal.repaso", category: "drag")

/// Which item is being dragged, and when the drag starts and ends (spec §4.4).
///
/// The system asks for the payload when an item lifts, which also happens when the user only opens its
/// context menu. So a lift is just *pending* until the session really moves (an iOS 27 session phase, or the
/// first hover over a target or screen catcher), and expires if no drag follows.
@Observable @MainActor
final class DragState {
    private(set) var active: DragRef?
    /// The folder screen the drag started on (nil = Home or Unsorted).
    private(set) var origin: UUID?
    private var pendingRef: DragRef?
    private var pendingOrigin: UUID?
    private var targeted = 0
    private var endCheck: Task<Void, Never>?
    private var pendingExpiry: Task<Void, Never>?

    static let pendingLifetime: Duration = .seconds(2.5)

    func lift(_ ref: DragRef, from origin: UUID?) {
        log.debug("lift \(ref.kind.rawValue)")
        pendingRef = ref
        pendingOrigin = origin
        pendingExpiry?.cancel()
        pendingExpiry = Task { [weak self] in
            try? await Task.sleep(for: Self.pendingLifetime)
            guard !Task.isCancelled, let self, self.active == nil else { return }
            self.pendingRef = nil
            self.pendingOrigin = nil
        }
    }

    /// The lifted item is really being dragged.
    func activate() {
        guard active == nil, let pendingRef else { return }
        log.debug("activate \(pendingRef.kind.rawValue)")
        pendingExpiry?.cancel()
        endCheck?.cancel()
        targeted = 0
        active = pendingRef
        origin = pendingOrigin
        self.pendingRef = nil
        pendingOrigin = nil
    }

    func end() {
        if active != nil || pendingRef != nil { log.debug("end") }
        endCheck?.cancel()
        pendingExpiry?.cancel()
        targeted = 0
        active = nil
        origin = nil
        pendingRef = nil
        pendingOrigin = nil
    }

    /// Drop targets and screen catchers report hover here. On iOS 26 this is also the end signal:
    /// nothing targeted for 0.3s means the drag is over.
    func setTargeted(_ isTargeted: Bool) {
        if isTargeted { activate() }
        guard active != nil else { return }
        targeted = max(0, targeted + (isTargeted ? 1 : -1))
        endCheck?.cancel()
        guard targeted == 0 else { return }
        endCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled, let self, self.targeted == 0 else { return }
            log.debug("fallback end")
            self.end()
        }
    }
}
