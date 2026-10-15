import SwiftUI

extension View {
    /// Bottom sheet in the Sheet glass material (radius 38).
    func repasoSheet(detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        presentationDetents(detents)
            .presentationCornerRadius(Theme.Radius.sheet)
            .presentationBackground {
                Theme.sheetFill.background(.ultraThinMaterial)
            }
            .presentationDragIndicator(.visible)
    }
}

/// Full-width 56pt pill: white for primary actions, rose for destructive ones.
struct PrimarySheetButton: View {
    let title: String
    var role: ButtonRole?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(role == .destructive ? .white : Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(role == .destructive ? Theme.rose : Theme.primaryButton, in: Capsule())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
    }
}

/// 28pt progress ring that turns into a green check.
struct ProgressRing: View {
    let progress: Double
    let done: Bool

    var body: some View {
        ZStack {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: progress)
            }
        }
        .frame(width: 28, height: 28)
        .animation(Theme.spring, value: done)
    }
}
