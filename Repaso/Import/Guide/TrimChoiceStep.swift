import SwiftUI
import RepasoCore

/// "Make clips from it?": the video plays with two big choices under it.
struct TrimChoiceStep: View {
    let recording: Recording
    let onMakeClips: () -> Void
    let onUseWhole: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var video: LoopingVideo?
    @State private var shown = false

    var body: some View {
        VStack(spacing: 18) {
            Group {
                if let video {
                    PlayerLayerView(player: video.player)
                } else {
                    Color.black
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 12)

            VStack(spacing: 10) {
                Button(action: onMakeClips) {
                    Label("Make clips", systemImage: "scissors")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.accent, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                Button(action: onUseWhole) {
                    Text("Use the whole video")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.rose)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .overlay(Capsule().strokeBorder(Theme.rose, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 12)
            .offset(y: shown || reduceMotion ? 0 : 40)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            if video == nil { video = LoopingVideo(url: env.videos.url(for: recording.fileName)) }
            video?.play()
            withAnimation(Theme.motion(reduceMotion).delay(0.15)) { shown = true }
        }
        .onDisappear { video?.pause() }
    }
}
