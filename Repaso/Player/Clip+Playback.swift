import Foundation
import RepasoCore

extension Clip {
    /// What the Player plays of its recording.
    var range: ClosedRange<Double> { start...max(start, end) }
}
