import SwiftUI

/// Main call to action: white 56pt pill floating 38pt from the bottom over a fade to `bg`.
struct FloatingPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 28)
                .frame(height: 56)
                .background(Theme.primaryButton, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.bottom, 38)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg], startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}
