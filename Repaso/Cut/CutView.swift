import SwiftUI
import SwiftData
import RepasoCore

/// Cut mode: play the original, Mark start → Mark end to create clips, trim them on the filmstrip.
struct CutView: View {
    let original: Original
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: CutModel?
    @State private var markCount = 0
    /// Set by the "Name" button on the clip-added toast: the tray starts renaming that clip.
    @State private var renameRequest: UUID?

    private var clips: [Clip] {
        FolderContents.sortClips(original.clips, by: .dateAdded)
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let model {
                content(model)
            }
        }
        .onAppear {
            if model == nil { model = CutModel(original: original, videos: env.videos) }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model?.tearDown()
        }
        .toastHost(env)
    }

    private func content(_ model: CutModel) -> some View {
        VStack(spacing: 18) {
            video(model)
            timeRow(model)
            markButton(model)
                .padding(.horizontal, Theme.gutter)
            Filmstrip(model: model, clips: clips) { clip, range in
                env.perform { try env.library(ctx).updateRange(clip, start: range.lowerBound, end: range.upperBound) }
            }
            .padding(.horizontal, Theme.gutter)
            ClipTray(model: model, clips: clips, renameRequest: $renameRequest) { clip, name in
                env.perform { try env.library(ctx).updateInfo(clip, name: name, note: clip.note ?? "") }
            }
            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: Video

    private func video(_ model: CutModel) -> some View {
        ZStack(alignment: .top) {
            if model.missingFile {
                Color.black.overlay(
                    Text("Video file missing").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.rose))
            } else {
                PlayerLayerView(player: model.player)
                    .contentShape(Rectangle())
                    .onTapGesture { model.togglePlay() }
                    .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                    .accessibilityAddTraits(.isButton)
            }
            (model.session.isRecording ? Theme.rose : Theme.accent)
                .keyframeAnimator(initialValue: 0.0, trigger: markCount) { view, opacity in
                    view.opacity(opacity)
                } keyframes: { _ in
                    MoveKeyframe(0.35)   // instant jump; a zero-length segment gives the next spring a NaN velocity
                    LinearKeyframe(0, duration: 0.5)
                }
                .allowsHitTesting(false)
            HStack {
                Button {
                    model.session.cancelMark()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                }
                .controlGlass(in: Capsule(), tint: Theme.overVideoTint)
                Spacer()
                Text(original.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .glassEffect(.regular.tint(Theme.overVideoTint), in: Capsule())
                Spacer()
                Color.clear.frame(width: 70, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 58)
        }
        .frame(height: 430)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous))
    }

    // MARK: Controls

    private func timeRow(_ model: CutModel) -> some View {
        VStack(spacing: 12) {
            Text("\(Text(TimeFormat.precise(model.time)).foregroundStyle(Theme.textPrimary))\(Text(" / \(TimeFormat.precise(model.duration))").foregroundStyle(Theme.textSecondary.opacity(0.7)))")
                .font(Theme.mono(30, weight: .semibold))
                .monospacedDigit()
                .accessibilityLabel("\(TimeFormat.precise(model.time)) of \(TimeFormat.precise(model.duration))")
            HStack(spacing: 28) {
                Button { model.jump(-5) } label: {
                    Text("−5s").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        .frame(width: 56, height: 44)
                }
                .controlGlass(in: Capsule())
                .accessibilityLabel("Back 5 seconds")
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 56, height: 56)
                        .background(Theme.primaryButton, in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                Button { model.jump(5) } label: {
                    Text("+5s").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        .frame(width: 56, height: 44)
                }
                .controlGlass(in: Capsule())
                .accessibilityLabel("Forward 5 seconds")
            }
        }
    }

    private func markButton(_ model: CutModel) -> some View {
        let recording = model.session.isRecording
        return Button { mark(model) } label: {
            HStack(spacing: 10) {
                if recording {
                    Circle()
                        .fill(Theme.onAccent)
                        .frame(width: 10, height: 10)
                        .phaseAnimator([1.0, 0.35]) { view, phase in
                            view.opacity(reduceMotion ? 1 : phase)
                        } animation: { _ in .easeInOut(duration: 0.6) }
                }
                Text(recording ? "Mark end" : "Mark start")
                if recording, let length = model.session.liveLength(at: model.time) {
                    Text(TimeFormat.length(length))
                        .font(Theme.mono(16, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(recording ? Theme.rose : Theme.accent, in: Capsule())
            .animation(.easeInOut(duration: 0.35), value: recording)
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: markCount)
    }

    private func mark(_ model: CutModel) {
        markCount += 1
        guard let range = model.session.mark(at: model.time) else {
            model.play()
            return
        }
        env.perform {
            let clip = try env.library(ctx).addClip(to: original, start: range.lowerBound, end: range.upperBound)
            model.selectedID = clip.id
            let request = $renameRequest
            let id = clip.id
            env.showToast("\(clip.name) added", actionTitle: "Name", undo: { request.wrappedValue = id }, seconds: 3.5)
        }
    }
}
