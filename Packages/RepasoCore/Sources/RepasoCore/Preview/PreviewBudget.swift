/// Hands out a fixed number of live-preview slots; the rest wait in arrival order.
public struct PreviewBudget<ID: Hashable> {
    public let capacity: Int
    public private(set) var granted: [ID] = []
    public private(set) var waiting: [ID] = []
    public private(set) var isEnabled = true

    public init(capacity: Int = 4) { self.capacity = capacity }

    public func isGranted(_ id: ID) -> Bool { granted.contains(id) }

    public mutating func request(_ id: ID) {
        guard !granted.contains(id), !waiting.contains(id) else { return }
        waiting.append(id)
        fill()
    }

    public mutating func release(_ id: ID) {
        granted.removeAll { $0 == id }
        waiting.removeAll { $0 == id }
        fill()
    }

    /// Disabling parks every granted id at the front of the queue, so re-enabling restores the same previews.
    public mutating func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if !on {
            waiting = granted + waiting
            granted = []
        }
        fill()
    }

    private mutating func fill() {
        guard isEnabled else { return }
        while granted.count < capacity, !waiting.isEmpty { granted.append(waiting.removeFirst()) }
    }
}
