import SwiftUI

extension View {
    /// Card: fill white 8%, 1pt white 15% border. Not live glass, so long lists stay cheap.
    func cardGlass(radius: CGFloat) -> some View {
        background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }

    /// Control: interactive Liquid Glass, optionally tinted (green/rose states).
    func controlGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? .regular.interactive(), in: shape)
    }

    /// Floating panel over video. Darkened, because clear glass over a bright frame washes out white text.
    func panelGlass(radius: CGFloat) -> some View {
        glassEffect(.regular.tint(Theme.overVideoTint), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
