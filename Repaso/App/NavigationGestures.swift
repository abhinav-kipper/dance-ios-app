import UIKit

/// Screens hide the navigation bar (each draws its own back button), which also switches off UIKit's swipe back.
/// This turns it on again whenever there is a screen to go back to: from the left edge, and on iOS 26 from
/// anywhere on the page.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        interactiveContentPopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
