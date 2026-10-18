import Foundation
import RepasoCore

/// What the Player plays: a clip's range, or a whole video from start to end.
enum PlaybackItem: Identifiable {
    case clip(Clip)
    case original(Original)

    var id: UUID {
        switch self {
        case .clip(let c): c.id
        case .original(let o): o.id
        }
    }

    var clip: Clip? {
        if case .clip(let c) = self { return c }
        return nil
    }

    var original: Original? {
        switch self {
        case .clip(let c): c.original
        case .original(let o): o
        }
    }

    var name: String {
        switch self {
        case .clip(let c): c.name
        case .original(let o): o.title
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .clip(let c): c.start...max(c.start, c.end)
        case .original(let o): 0...max(0, o.duration)
        }
    }

    var length: Double { range.upperBound - range.lowerBound }

    var note: String? {
        switch self {
        case .clip(let c): c.note
        case .original(let o): o.note
        }
    }

    /// Clips remember their zoom; whole videos start unzoomed each time.
    var framing: Framing { clip?.framing ?? .identity }
}
