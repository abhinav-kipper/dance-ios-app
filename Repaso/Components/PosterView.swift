import SwiftUI
import RepasoCore

/// Cached poster frame for a clip or original; neutral placeholder until it loads.
struct PosterView: View {
    let request: ThumbnailRequest?
    var cornerRadius: CGFloat = Theme.Radius.thumb
    @Environment(AppEnvironment.self) private var env
    @State private var image: CGImage?

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: "film").foregroundStyle(.white.opacity(0.3))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: request) {
                guard let request else {
                    image = nil
                    return
                }
                image = await env.thumbnails.image(for: request)
            }
            .accessibilityHidden(true)
    }
}
