public enum ClipRange {
    public static let minLength = 0.5

    /// Orders the endpoints, clamps them to [0, duration], and enforces `minLength`
    /// (or the whole video when it is shorter than `minLength`).
    public static func normalized(start: Double, end: Double, duration: Double, minLength: Double = minLength) -> ClosedRange<Double> {
        let d = max(0, duration)
        var a = min(max(0, min(start, end)), d)
        var b = min(max(0, max(start, end)), d)
        if b - a < minLength {
            b = min(a + minLength, d)
            a = max(0, b - minLength)
        }
        return a...b
    }
}
