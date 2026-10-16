import SwiftUI
import RepasoCore

/// Glass chip shown while stepping frames on a paused clip: ‹ Frame 0412 ›.
struct FrameChip: View {
    let frame: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.left")
            Text(TimeFormat.frame(frame))
                .font(Theme.mono(15))
                .contentTransition(.numericText())
            Image(systemName: "chevron.right")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TimeFormat.frame(frame))
    }
}
