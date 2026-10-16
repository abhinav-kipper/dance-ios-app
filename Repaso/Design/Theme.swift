import SwiftUI

enum Theme {
    static let bg = Color(red: 3 / 255, green: 3 / 255, blue: 3 / 255)
    static let textPrimary = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let textSecondary = Color.white.opacity(0.72)
    static let accent = Color(red: 191 / 255, green: 1, blue: 60 / 255)
    static let onAccent = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let accentTint = accent.opacity(0.15)
    static let rose = Color(red: 1, green: 77 / 255, blue: 141 / 255)
    static let roseTint = rose.opacity(0.17)
    static let primaryButton = Color.white.opacity(0.93)
    static let sheetFill = Color(red: 48 / 255, green: 48 / 255, blue: 54 / 255).opacity(0.74)
    static let gutter: CGFloat = 20

    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.7)

    /// The standard spring, or a plain ease-out under Reduce Motion (no overshoot).
    static func motion(_ reduceMotion: Bool, _ animation: Animation = spring) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : animation
    }

    enum Radius {
        static let folderCard: CGFloat = 24
        static let listCard: CGFloat = 22
        static let mosaic: CGFloat = 17
        static let thumb: CGFloat = 9
        static let panel: CGFloat = 32
        static let sheet: CGFloat = 38
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Small uppercase section label (13pt semibold, +6% tracking).
    func sectionLabelStyle(_ color: Color = Theme.textSecondary) -> some View {
        font(.system(size: 13, weight: .semibold))
            .textCase(.uppercase)
            .tracking(13 * 0.06)
            .foregroundStyle(color)
    }
}
