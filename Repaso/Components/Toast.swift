import SwiftUI

struct ToastView: View {
    let toast: ToastState
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 48)
        .glassEffect(.regular, in: Capsule())
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Hosts the app-wide toast above the bottom pill.
    func toastHost(_ env: AppEnvironment) -> some View {
        overlay(alignment: .bottom) {
            if let toast = env.toast {
                ToastView(toast: toast) { env.toast = nil }
                    .padding(.bottom, 110)
            }
        }
        .animation(Theme.spring, value: env.toast?.id)
    }
}
