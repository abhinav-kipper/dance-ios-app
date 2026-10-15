import SwiftUI

/// 0.5× / 0.75× / 1× segmented control with a sliding green pill.
struct SpeedControl: View {
    static let speeds: [Double] = [0.5, 0.75, 1]

    @Binding var speed: Double
    var onChange: () -> Void = {}
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.speeds, id: \.self) { value in
                let active = abs(value - speed) < 0.01
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { speed = value }
                    onChange()
                } label: {
                    Text(Self.label(value))
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(active ? Theme.onAccent : Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if active {
                                Capsule().fill(Theme.accent).matchedGeometryEffect(id: "speedPill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Speed \(Self.label(value))")
                .accessibilityIdentifier("speed-\(value)")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(minHeight: 44)
        .controlGlass(in: Capsule())
    }

    static func label(_ value: Double) -> String {
        value == 1 ? "1×" : "\(value.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}
