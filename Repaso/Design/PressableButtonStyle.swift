import SwiftUI

/// Scales to 0.93 while pressed (plain ease under Reduce Motion).
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : Theme.spring, value: configuration.isPressed)
    }
}
