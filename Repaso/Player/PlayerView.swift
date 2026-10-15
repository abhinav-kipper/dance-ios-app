import SwiftUI
import SwiftData
import RepasoCore

/// Full-screen clip player: tap to play/pause, speed, loop, pause-before-repeat, favorite, learned.
struct PlayerView: View {
    let request: PlayerRequest
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("playbackSpeed") private var speed = 1.0
    @State private var model = PlayerModel()
    @State private var chromeVisible = true
    @State private var idleTask: Task<Void, Never>?
    @State private var flash = 0
    @State private var ringProgress: Double = 1
    @State private var deletingOriginal: Original?

    private var clip: Clip { request.queue[request.index] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.missingFile {
                missingFileCard
            } else {
                PlayerLayerView(player: model.player)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.togglePlay()
                        flash += 1
                        wake()
                    }
                    .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                    .accessibilityAddTraits(.isButton)
            }
            flashOverlay
            if let seconds = model.restingSeconds { restRing(seconds) }
            VStack {
                topBar
                Spacer()
                panel
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            model.speed = speed
            model.load(clip, videos: env.videos)
            env.perform { try env.library(ctx).markPlayed(clip) }
            wake()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            idleTask?.cancel()
            model.tearDown()
        }
        .onChange(of: speed) { _, new in model.speed = new }
        .onChange(of: model.isPlaying) { _, _ in wake() }
        .sheet(item: $deletingOriginal) { original in
            DeleteOriginalSheet(original: original) { dismiss() }
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .controlGlass(in: Circle())
            .accessibilityLabel("Close player")
            Spacer()
            Text("\(request.title) \(request.index + 1) / \(request.queue.count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .glassEffect(.regular, in: Capsule())
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .opacity(chromeVisible ? 1 : 0)
        .offset(y: chromeVisible || reduceMotion ? 0 : -12)
        .allowsHitTesting(chromeVisible)
        .animation(.easeOut(duration: 0.5), value: chromeVisible)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(clip.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(TimeFormat.duration(clip.length))
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(source)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .padding(.top, -10)
            if let note = clip.note {
                Text(note)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
            }
            Capsule()
                .fill(.white.opacity(0.18))
                .frame(height: 3)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(.white).frame(width: geo.size.width * model.progress)
                    }
                }
                .accessibilityHidden(true)
            SpeedControl(speed: $speed, onChange: wake)
            HStack(spacing: 8) {
                loopButton
                gapButton
                Spacer()
                favoriteButton
                learnedButton
            }
        }
        .padding(.init(top: 18, leading: 16, bottom: 14, trailing: 16))
        .panelGlass(radius: Theme.Radius.panel)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .opacity(chromeVisible || !model.isPlaying ? 1 : 0.42)
        .animation(.easeOut(duration: 0.6), value: chromeVisible)
        .simultaneousGesture(TapGesture().onEnded { wake() })
    }

    private var source: String {
        guard let original = clip.original else { return "" }
        guard let recorded = original.recordedAt else { return original.title }
        return "\(original.title) · \(recorded.formatted(date: .abbreviated, time: .omitted))"
    }

    private var loopButton: some View {
        let on = model.loop.loopEnabled
        return Button {
            model.toggleLoop()
            wake()
        } label: {
            Label("Loop", systemImage: "repeat")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Theme.accent : Theme.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(on ? Theme.accentTint : .white.opacity(0.15), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(on ? "Loop on" : "Loop off")
    }

    private var gapButton: some View {
        let gap = model.loop.gap
        return Button {
            model.cycleGap()
            wake()
        } label: {
            Label(gap.label, systemImage: "timer")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(gap == .none ? Theme.textSecondary : Theme.accent)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(gap == .none ? .white.opacity(0.15) : Theme.accentTint, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .opacity(model.loop.loopEnabled ? 1 : 0.4)
        .disabled(!model.loop.loopEnabled)
        .accessibilityLabel("Pause before repeat: \(gap == .none ? "none" : "\(gap.rawValue) seconds")")
    }

    private var favoriteButton: some View {
        Button {
            env.perform { try env.library(ctx).toggleFavorite(clip) }
            wake()
        } label: {
            Image(systemName: clip.isFavorite ? "star.fill" : "star")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(clip.isFavorite ? Theme.rose : Theme.textPrimary)
                .symbolEffect(.bounce, value: clip.isFavorite)
                .frame(width: 44, height: 44)
                .background(clip.isFavorite ? Theme.roseTint : .white.opacity(0.15), in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(clip.isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private var learnedButton: some View {
        Button {
            env.perform { try env.library(ctx).toggleLearned(clip) }
            wake()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(clip.isLearned ? Theme.onAccent : Theme.textPrimary)
                .symbolEffect(.bounce, value: clip.isLearned)
                .frame(width: 44, height: 44)
                .background(clip.isLearned ? Theme.accent : .white.opacity(0.15), in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.success, trigger: clip.isLearned) { _, new in new }
        .accessibilityLabel(clip.isLearned ? "Mark as not learned" : "Mark as learned")
    }

    // MARK: Overlays

    private var flashOverlay: some View {
        Image(systemName: model.isPlaying ? "play.fill" : "pause.fill")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 96, height: 96)
            .glassEffect(.regular, in: Circle())
            .keyframeAnimator(initialValue: FlashValues(), trigger: flash) { view, value in
                view.scaleEffect(value.scale).opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.6, duration: 0)
                    SpringKeyframe(1, duration: 0.25)
                    LinearKeyframe(1.35, duration: 0.45)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0)
                    LinearKeyframe(1, duration: 0.25)
                    LinearKeyframe(0, duration: 0.45)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func restRing(_ seconds: Double) -> some View {
        VStack(spacing: 10) {
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 72, height: 72)
            Text("Again in \(Int(seconds))s")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .onAppear {
            ringProgress = 1
            withAnimation(.linear(duration: seconds)) { ringProgress = 0 }
        }
        .allowsHitTesting(false)
    }

    private var missingFileCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Theme.rose)
            Text("Video file missing")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Button("Delete video") { deletingOriginal = clip.original }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(Theme.rose, in: Capsule())
        }
        .padding(28)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Idle

    /// Shows chrome, then hides the top bar and dims the panel after 2.4s of playback.
    private func wake() {
        chromeVisible = true
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled, model.isPlaying else { return }
            chromeVisible = false
        }
    }
}

private struct FlashValues {
    var scale: Double = 0.6
    var opacity: Double = 0
}
