import SwiftUI
import RepasoCore

/// Cached poster frame for a clip or original; neutral placeholder until it loads.
/// With `live`, a muted looping preview plays over the poster whenever the app grants it a slot.
struct PosterView: View {
    let request: ThumbnailRequest?
    var cornerRadius: CGFloat = Theme.Radius.thumb
    var live: PreviewSource?
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
            .overlay {
                if let live, env.previews.isGranted(live.id) {
                    LivePreviewView(source: live, url: env.videos.url(for: live.fileName))
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
            // Slots go to posters actually on screen; lists here are non-lazy, so onAppear fires for every row.
            .onScrollVisibilityChange(threshold: 0.5) { visible in
                guard let live else { return }
                if visible { env.previews.request(live.id) } else { env.previews.release(live.id) }
            }
            .onDisappear { if let live { env.previews.release(live.id) } }
            .accessibilityHidden(true)
    }
}
