import Foundation

/// A clip's remembered zoom and pan. Pan is a fraction of the video view's size, so it survives device changes.
public struct Framing: Equatable, Sendable {
    public var zoom: Double
    public var panX: Double
    public var panY: Double

    public static let identity = Framing(zoom: 1, panX: 0, panY: 0)
    public static let zoomRange: ClosedRange<Double> = 1...3

    public init(zoom: Double, panX: Double, panY: Double) {
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
    }

    /// Zoom within 1…3, pan within ±(zoom−1)/2 so the video always covers the view; ~1× snaps to identity.
    public func clamped() -> Framing {
        let z = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        guard z > 1.01 else { return .identity }
        let limit = (z - 1) / 2
        return Framing(zoom: z, panX: min(max(panX, -limit), limit), panY: min(max(panY, -limit), limit))
    }

    public var isZoomed: Bool { zoom > 1.01 }

    public var label: String { String(format: "%.1f×", zoom) }
}

extension Clip {
    public var framing: Framing { Framing(zoom: zoom, panX: panX, panY: panY) }
}
