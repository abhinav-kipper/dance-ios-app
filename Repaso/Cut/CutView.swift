import SwiftUI
import SwiftData
import RepasoCore

/// Cut mode: play the original, Mark start → Mark end to create clips, trim them on the filmstrip.
struct CutView: View {
    let original: Original
    /// Trim…: this clip starts selected, with the strip at it.
    var focusClipID: UUID?
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: CutModel?
    @State private var markCount = 0
    /// Set by the "Name" button on the clip-added toast: the tray starts renaming that clip.
    @State private var renameRequest: UUID?
    /// Swipe down on the video to close Cut, like closing a photo.
    @State private var closeDrag: CGFloat = 0
    /// Clips the video had when Cut opened; making more prompts "Keep the full video?" on Done.
    @State private var clipsAtOpen: Int?
    @State private var askKeep = false
    /// Saving clips as their own videos: (finished, total).
    @State private var keeping: (Int, Int)?
    /// The Mark button explains itself ("where the move begins") until the first clip is cut.
    @AppStorage("hint.cut.marked") private var hasMarked = false

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
            if model == nil {
                let made = CutModel(original: original, videos: env.videos)
                if let focusClipID, let clip = original.clips.first(where: { $0.id == focusClipID }) {
                    made.selectedID = clip.id
                    made.seek(clip.start)
                }
                model = made
                clipsAtOpen = original.clips.count
            }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model?.tearDown()
        }
        .overlay { if let keeping { keepingOverlay(keeping) } }
        .confirmationDialog("Keep the full video?", isPresented: $askKeep, titleVisibility: .visible) {
            Button("Keep full video") { dismiss() }
            Button("Keep only the clips", role: .destructive, action: keepOnlyClips)
            Button("Not now", role: .cancel) {}
        } message: {
            Text(keepMessage)
        }
        .toastHost(env)
    }

    private var keepMessage: String {
        let n = original.clips.count
        let clips = n == 1 ? "Your clip is saved." : "Your \(n) clips are saved."
        let size = ClipKeeper.sizeText(of: original, env: env).map { " and frees \($0)" } ?? ""
        return "\(clips) Keeping only the clips deletes the full video\(size). You can still trim each clip within its length."
    }

    /// Done (or a pull down): asks about the full video if clips were made this time, otherwise closes.
    private func finish(_ model: CutModel) {
        model.session.cancelMark()
        if let clipsAtOpen, original.clips.count > clipsAtOpen, !original.isClipSource {
            askKeep = true
        } else {
            dismiss()
        }
    }

    private func keepOnlyClips() {
        model?.pause()
        let count = original.clips.count   // they move to their own videos as they're saved
        keeping = (0, count)
        let original = original
        let env = env
        let ctx = ctx
        Task {
            do {
                try await ClipKeeper.saveClipsAsOwnVideos(of: original, env: env, context: ctx) { done, total in
                    keeping = (done, total)
                }
                dismiss()
                try? await Task.sleep(for: .seconds(0.5))   // the cutter must be gone before its video is
                env.perform { try env.library(ctx).deleteOriginal(original) }
                env.showToast(count == 1 ? "Full video deleted · 1 clip kept" : "Full video deleted · \(count) clips kept")
            } catch {
                keeping = nil
                env.showToast("Couldn't save the clips; the full video is kept", seconds: 3)
            }
        }
    }

    private func keepingOverlay(_ progress: (Int, Int)) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: Double(progress.0), total: Double(max(progress.1, 1)))
                    .tint(Theme.accent)
                    .frame(width: 200)
                Text("Saving clip \(min(progress.0 + 1, progress.1)) of \(progress.1)…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(24)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    private func content(_ model: CutModel) -> some View {
        // The video takes every point the controls don't need.
        VStack(spacing: 12) {
            video(model)
                .frame(maxHeight: .infinity)
            Filmstrip(model: model, clips: clips) { clip, range in
                env.perform { try env.library(ctx).updateRange(clip, start: range.lowerBound, end: range.upperBound) }
            }
            .padding(.horizontal, Theme.gutter)
            markButton(model)
                .padding(.horizontal, Theme.gutter)
            ClipTray(model: model, clips: clips, renameRequest: $renameRequest) { clip, name in
                env.perform { try env.library(ctx).updateInfo(clip, name: name, note: clip.note ?? "") }
            }
            .padding(.bottom, 4)
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
                    .gesture(closeGesture(model))
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
                    finish(model)
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
            if !model.missingFile { videoControls(model) }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34, style: .continuous))
        .offset(y: closeDrag)
        .scaleEffect(1 - min(closeDrag, 300) / 1500, anchor: .top)
    }

    /// Pull the video down to close; a short pull springs back.
    private func closeGesture(_ model: CutModel) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let dy = value.translation.height
                guard dy > 0, dy > abs(value.translation.width) else { return }
                closeDrag = dy * 0.6
            }
            .onEnded { value in
                if value.translation.height > 110 || value.predictedEndTranslation.height > 260 {
                    withAnimation(Theme.motion(reduceMotion)) { closeDrag = 0 }
                    finish(model)
                } else {
                    withAnimation(Theme.motion(reduceMotion)) { closeDrag = 0 }
                }
            }
    }

    // MARK: Controls

    /// Over the bottom of the video, like the Player: where you are on the left, play/pause on the right.
    private func videoControls(_ model: CutModel) -> some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                HStack(spacing: 4) {
                    Text(TimeFormat.precise(model.time))
                        .foregroundStyle(Theme.textPrimary)
                    Text("/ \(TimeFormat.precise(model.duration))")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(Theme.mono(14, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .frame(height: 36)
                .glassEffect(.regular.tint(Theme.overVideoTint), in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(TimeFormat.precise(model.time)) of \(TimeFormat.precise(model.duration))")
                Spacer()
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 52, height: 52)
                }
                .controlGlass(in: Circle(), tint: Theme.overVideoTint)
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
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
                VStack(spacing: 1) {
                    HStack(spacing: 10) {
                        Text(recording ? "Mark end" : "Mark start")
                        if recording, let length = model.session.liveLength(at: model.time) {
                            Text(TimeFormat.length(length))
                                .font(Theme.mono(16, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                    if !hasMarked {
                        Text(recording ? "where the move ends" : "where the move begins")
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.7)
                            .transition(.opacity)
                    }
                }
            }
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(recording ? Theme.rose : Theme.accent, in: Capsule())
            .animation(.easeInOut(duration: 0.35), value: recording)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(markLabel(model))
        .accessibilityHint(recording ? "Marks where the move ends" : "Marks where the move begins")
        .sensoryFeedback(.impact(weight: .medium), trigger: markCount)
    }

    /// "Mark start", or "Mark end, 2.4 seconds" while recording.
    private func markLabel(_ model: CutModel) -> String {
        guard model.session.isRecording else { return "Mark start" }
        return model.session.liveLength(at: model.time).map { "Mark end, \(TimeFormat.length($0))" } ?? "Mark end"
    }

    private func mark(_ model: CutModel) {
        markCount += 1
        guard let range = model.session.mark(at: model.time) else {
            model.play()
            return
        }
        env.perform {
            let clip = try env.library(ctx).addClip(to: original, start: range.lowerBound, end: range.upperBound)
            withAnimation(.easeOut(duration: 0.3)) { hasMarked = true }
            model.selectedID = clip.id
            let request = $renameRequest
            let id = clip.id
            env.showToast("\(clip.name) added", actionTitle: "Name", undo: { request.wrappedValue = id }, seconds: 3.5)
        }
    }
}
