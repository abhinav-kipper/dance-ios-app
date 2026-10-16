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
    @State private var sharing: Clip?
    @State private var index: Int
    // Swipe between clips
    @State private var gestureMode: PlayerGesture.Mode?
    @State private var swipeOffset: CGFloat = 0
    @State private var entryOffset: CGFloat = 0
    @State private var entryOpacity: Double = 1
    // Frame stepping
    @State private var stepped = 0
    @State private var steps = 0
    @State private var showFrameChip = false
    // Zoom and pan
    @State private var framing = Framing.identity
    @State private var baseFraming = Framing.identity
    @State private var isPinching = false
    /// A pinch began during the current one-finger drag, so that drag must not swipe, scrub or pan.
    @State private var dragHadPinch = false
    @State private var isDragging = false
    @State private var videoSize = CGSize(width: 1, height: 1)
    @State private var resets = 0

    init(request: PlayerRequest) {
        self.request = request
        _index = State(initialValue: request.index)
    }

    private var clip: Clip { request.queue[index] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                if model.missingFile {
                    missingFileCard
                } else {
                    video
                }
                flashOverlay
                if let seconds = model.restingSeconds { restRing(seconds) }
            }
            .offset(y: swipeOffset + entryOffset)
            .opacity(entryOpacity * (1 - min(abs(swipeOffset) / 260, 0.5)))
            VStack {
                topBar
                Spacer()
                if showFrameChip {
                    FrameChip(frame: model.frameIndex)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                }
                panel
            }
            .animation(.easeOut(duration: 0.2), value: showFrameChip)
            if request.queue.count > 1 {
                PageIndicator(count: request.queue.count, index: index)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: index)
        .sensoryFeedback(.selection, trigger: steps)
        .sensoryFeedback(.impact(weight: .light), trigger: resets)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            model.speed = speed
            loadCurrentClip()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            idleTask?.cancel()
            model.tearDown()
        }
        .onChange(of: speed) { _, new in model.speed = new }
        .onChange(of: model.isPlaying) { _, playing in
            if playing { showFrameChip = false }
            wake()
        }
        .sheet(item: $sharing) { ShareSheet(clip: $0) }
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
            Text("\(request.title) \(index + 1) / \(request.queue.count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .glassEffect(.regular, in: Capsule())
            Spacer()
            if framing.isZoomed {
                Button(action: resetZoom) {
                    Text("\(framing.label) Reset")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                }
                .controlGlass(in: Capsule())
                .accessibilityLabel("Reset zoom")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                AirPlayButton()
                    .frame(width: 44, height: 44)
                    .controlGlass(in: Circle())
                    .accessibilityLabel("AirPlay")
                    .transition(.opacity)
            }
        }
        .animation(Theme.motion(reduceMotion), value: framing.isZoomed)
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
                shareButton
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
        // Tagged at import: "Ataca & Alemana · Berlin 2026".
        let tags = [original.instructors.joined(separator: " & "), original.event ?? ""].filter { !$0.isEmpty }
        if !tags.isEmpty { return tags.joined(separator: " · ") }
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

    private var shareButton: some View {
        Button {
            model.pause()
            sharing = clip
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.15), in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Share clip")
    }

    // MARK: Video and gestures

    private var video: some View {
        PlayerLayerView(player: model.player)
            .scaleEffect(framing.zoom)
            .offset(x: framing.panX * videoSize.width, y: framing.panY * videoSize.height)
            .clipped()
            .ignoresSafeArea()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { videoSize = $0 }
            .animation(isPinching || gestureMode == .pan ? nil : Theme.motion(reduceMotion), value: framing)
            .contentShape(Rectangle())
            .onTapGesture {
                model.togglePlay()
                flash += 1
                wake()
            }
            .simultaneousGesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .gesture(TwoFingerTap(action: resetZoom))
            .accessibilityElement()
            .accessibilityIdentifier("Video")
            .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: go(by: 1)
                case .decrement: go(by: -1)
                @unknown default: break
                }
            }
    }

    /// One finger: swipe between clips, step frames when paused, or pan when zoomed (decided once per drag).
    private var dragGesture: some Gesture {
        // Global space: the video moves with the finger, so local translation would shrink.
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                isDragging = true
                guard !isPinching, !dragHadPinch else { return }
                let dx = value.translation.width, dy = value.translation.height
                if gestureMode == nil {
                    gestureMode = PlayerGesture.classify(dx: dx, dy: dy, isZoomed: framing.isZoomed, isPlaying: model.isPlaying)
                    if gestureMode == .pan { baseFraming = framing }
                    if gestureMode == .scrub && !model.canStep { gestureMode = nil }
                }
                switch gestureMode {
                case .swipe:
                    swipeOffset = dy * PlayerGesture.followFactor
                case .scrub:
                    let target = PlayerGesture.frames(forDrag: dx)
                    if target != stepped {
                        model.step(by: target - stepped)
                        stepped = target
                        steps += 1
                    }
                    showChip()
                case .pan:
                    framing = Framing(zoom: baseFraming.zoom,
                                      panX: baseFraming.panX + dx / videoSize.width,
                                      panY: baseFraming.panY + dy / videoSize.height).clamped()
                case nil:
                    break
                }
                wake()
            }
            .onEnded { value in
                defer {
                    gestureMode = nil
                    stepped = 0
                    dragHadPinch = false
                    isDragging = false
                }
                if dragHadPinch {
                    withAnimation(Theme.motion(reduceMotion)) { swipeOffset = 0 }
                    return
                }
                switch gestureMode {
                case .swipe: finishSwipe(dy: value.translation.height)
                case .pan: saveFraming()
                case .scrub: break   // the chip stays while paused; playing again hides it
                case nil: break
                }
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !isPinching {
                    isPinching = true
                    dragHadPinch = true
                    baseFraming = framing
                    withAnimation(Theme.motion(reduceMotion)) { swipeOffset = 0 }
                }
                framing = Framing(zoom: baseFraming.zoom * value.magnification,
                                  panX: baseFraming.panX, panY: baseFraming.panY).clamped()
                wake()
            }
            .onEnded { _ in
                isPinching = false
                if !isDragging { dragHadPinch = false }   // no drag to clear it at its end
                saveFraming()
            }
    }

    private func finishSwipe(dy: CGFloat) {
        let direction = PlayerGesture.swipeDirection(dy: dy)
        if direction != 0, ClipQueue.step(from: index, by: direction, count: request.queue.count) != nil {
            swipeOffset = 0
            go(by: direction)
        } else {
            withAnimation(Theme.motion(reduceMotion)) { swipeOffset = 0 }
        }
    }

    /// Moves to the next (+1) or previous (−1) clip; the new one slides in from 120pt (fades under Reduce Motion).
    private func go(by direction: Int) {
        guard let next = ClipQueue.step(from: index, by: direction, count: request.queue.count) else { return }
        index = next
        if reduceMotion {
            entryOpacity = 0
            withAnimation(.easeOut(duration: 0.25)) { entryOpacity = 1 }
        } else {
            entryOffset = CGFloat(direction) * PlayerGesture.slideInDistance
            withAnimation(Theme.spring) { entryOffset = 0 }
        }
        loadCurrentClip()
    }

    private func loadCurrentClip() {
        framing = clip.framing
        showFrameChip = false
        model.load(clip, videos: env.videos)
        env.perform { try env.library(ctx).markPlayed(clip) }
        wake()
    }

    private func saveFraming() {
        let clip = clip
        let framing = framing
        env.perform { try env.library(ctx).setFraming(clip, framing) }
    }

    private func resetZoom() {
        guard framing.isZoomed else { return }
        withAnimation(Theme.motion(reduceMotion)) { framing = .identity }
        resets += 1
        saveFraming()
        wake()
    }

    private func showChip() {
        showFrameChip = true
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
