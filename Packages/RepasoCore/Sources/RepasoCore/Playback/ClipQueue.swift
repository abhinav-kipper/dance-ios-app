public enum ClipQueue {
    /// The neighbouring index, or nil past either end (no wrap-around).
    public static func step(from index: Int, by direction: Int, count: Int) -> Int? {
        let next = index + direction
        return direction != 0 && (0..<count).contains(next) ? next : nil
    }
}
