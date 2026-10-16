import SwiftUI
import UIKit
import RepasoCore

/// Long press on the left or right third of the video to step frames (UIKit, because SwiftUI's long press doesn't report
/// where it started). Doesn't cancel other touches, so taps and drags keep working alongside it.
struct HoldSeekGesture: UIGestureRecognizerRepresentable {
    let onBegin: (HoldSeek.Zone) -> Void
    let onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = HoldSeek.minimumHold
        recognizer.allowableMovement = 10
        recognizer.cancelsTouchesInView = false
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            let width = recognizer.view?.bounds.width ?? 0
            onBegin(HoldSeek.zone(forX: recognizer.location(in: recognizer.view).x, width: width))
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }
}
