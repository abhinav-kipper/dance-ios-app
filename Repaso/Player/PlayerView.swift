import SwiftUI
import SwiftData
import RepasoCore

/// Full-screen player for clips or whole videos: tap to play/pause, hold a side to step frames, speed, loop,
/// pause-before-repeat, favorite, learned. The control panel slides away while playing.
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
    // Hold to seek
    @State private var holdEndedAt: Date?
    // Sliding panel
    @State private var panelHidden = false
    @State private var panelHeight: CGFloat = 0
    @State private var panelDrag: CGFloat = 0
    // Rename
    @State private var renaming = false
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    init(request: PlayerRequest) {
        self.request = request
        _index = State(initialValue: request.index)
    }

    private var item: PlaybackItem { request.items[index] }
    /// nil while playing a whole video.
    private var clip: Clip? { item.clip }

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
            if request.items.count > 1 {
                PageIndicator(count: request.items.count, index: index)
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
            if playing { showFrameChip = false } else { showPanel() }   // paused: controls come back
            wake()
        }
        .onChange(of: model.frameIndex) { _, _ in
            if model.holdZone != .none { steps += 1 }   // a light tick per frame while holding
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
            Text("\(request.title) \(index + 1) / \(request.items.count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .glassEffect(.regular.tint(Theme.overVideoTint), in: Capsule())
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
                // A plain fill, not Liquid Glass: the route picker redraws itself when AirPlay connects.
                AirPlayButton()
                    .frame(width: 44, height: 44)
                    .background(Theme.overVideoTint, in: Circle())
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
            grabber
            HStack(alignment: .firstTextBaseline) {
                nameView
                Spacer()
                Text(TimeFormat.duration(item.length))
                    .font(Theme.mono(14))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(source)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .padding(.top, -10)
            if let note = item.note {
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
                if clip != nil {
                    favoriteButton
                    learnedButton
                    shareButton
                }
            }
        }
        .padding(.init(top: 6, leading: 16, bottom: 14, trailing: 16))
        .panelGlass(radius: Theme.Radius.panel)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
        .offset(y: panelOffset)
        .opacity(panelHidden ? 0.6 : (chromeVisible || !model.isPlaying ? 1 : 0.42))
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring, value: panelHidden)
        .animation(.easeOut(duration: 0.6), value: chromeVisible)
        .simultaneousGesture(TapGesture().onEnded { wake() })
    }

    /// Slid away = only the grabber peeks out (36pt); a drag follows the finger.
    private var panelOffset: CGFloat {
        let hiddenOffset = reduceMotion ? 0 : max(0, panelHeight - 44)
        return max(0, (panelHidden ? hiddenOffset : 0) + panelDrag)
    }

    /// Drag (or tap) the grabber to bring the panel up or send it down.
    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(0.5))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape([.interaction, .accessibility], Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        panelDrag = panelHidden ? min(0, value.translation.height) : max(0, value.translation.height)
                    }
                    .onEnded { value in
                        let dy = value.predictedEndTranslation.height
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring) {
                            if panelHidden && dy < -30 { panelHidden = false }
                            if !panelHidden && dy > 40 { panelHidden = true }
                            panelDrag = 0
                        }
                        if !panelHidden { wake() }
                    }
            )
            .onTapGesture {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring) { panelHidden.toggle() }
                if !panelHidden { wake() }
            }
            .accessibilityLabel(panelHidden ? "Show controls" : "Hide controls")
            .accessibilityAddTraits(.isButton)
    }

    /// Clip names rename in place: tap, type, return.
    @ViewBuilder
    private var nameView: some View {
        if renaming, let clip {
            TextField(clip.name, text: $nameDraft)   // the current name shows as the hint
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { commitRename(clip) }
                .onChange(of: nameFocused) { _, focused in if !focused { commitRename(clip) } }
                .accessibilityLabel("Clip name")
                .accessibilityIdentifier("Clip name")
        } else {
            Text(item.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard clip != nil else { return }
                    nameDraft = ""   // empty: typing replaces the name; return with nothing keeps it
                    renaming = true
                    nameFocused = true
                    showPanel()
                }
                .accessibilityAddTraits(clip == nil ? [] : .isButton)
                .accessibilityHint(clip == nil ? "" : "Renames the clip")
                .accessibilityIdentifier("player-clip-name")
        }
    }

    private func commitRename(_ clip: Clip) {
        guard renaming else { return }
        renaming = false
        let name = nameDraft
        env.perform { try env.library(ctx).updateInfo(clip, name: name, note: clip.note ?? "") }
        wake()
    }

    private func showPanel() {
        guard panelHidden else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring) { panelHidden = false }
    }

    private var source: String {
        guard let original = item.original else { return "" }
        if clip == nil { return original.recordedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Whole video" }
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
                .lineLimit(1)
                .fixedSize()
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
            Label(gap.shortLabel, systemImage: "timer")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize()
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
            guard let clip else { return }
            env.perform { try env.library(ctx).toggleFavorite(clip) }
            wake()
        } label: {
            Image(systemName: (clip?.isFavorite ?? false) ? "star.fill" : "star")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle((clip?.isFavorite ?? false) ? Theme.rose : Theme.textPrimary)
                .symbolEffect(.bounce, value: clip?.isFavorite ?? false)
                .frame(width: 44, height: 44)
                .background((clip?.isFavorite ?? false) ? Theme.roseTint : .white.opacity(0.15), in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel((clip?.isFavorite ?? false) ? "Remove from favorites" : "Add to favorites")
    }

    private var learnedButton: some View {
        Button {
            guard let clip else { return }
            env.perform { try env.library(ctx).toggleLearned(clip) }
            wake()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle((clip?.isLearned ?? false) ? Theme.onAccent : Theme.textPrimary)
                .symbolEffect(.bounce, value: clip?.isLearned ?? false)
                .frame(width: 44, height: 44)
                .background((clip?.isLearned ?? false) ? Theme.accent : .white.opacity(0.15), in: Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .sensoryFeedback(.success, trigger: clip?.isLearned ?? false) { _, new in new }
        .accessibilityLabel((clip?.isLearned ?? false) ? "Mark as not learned" : "Mark as learned")
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
                // A long press also ends with a lift; that lift isn't a tap.
                if let ended = holdEndedAt, Date.now.timeIntervalSince(ended) < 0.4 { return }
                guard model.holdZone == .none else { return }
                model.togglePlay()
                flash += 1
                wake()
            }
            .gesture(HoldSeekGesture(onBegin: { zone in
                guard !isPinching, gestureMode == nil else { return }
                model.beginHold(zone)
                if model.holdZone != .none { showChip() }
            }, onEnd: {
                guard model.holdZone != .none else { return }
                model.endHold()
                holdEndedAt = .now
            }))
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
        if direction != 0, ClipQueue.step(from: index, by: direction, count: request.items.count) != nil {
            swipeOffset = 0
            go(by: direction)
        } else {
            withAnimation(Theme.motion(reduceMotion)) { swipeOffset = 0 }
        }
    }

    /// Moves to the next (+1) or previous (−1) clip; the new one slides in from 120pt (fades under Reduce Motion).
    private func go(by direction: Int) {
        guard let next = ClipQueue.step(from: index, by: direction, count: request.items.count) else { return }
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
        framing = item.framing
        showFrameChip = false
        renaming = false
        model.load(item, videos: env.videos)
        if let clip { env.perform { try env.library(ctx).markPlayed(clip) } }
        showPanel()
        wake()
    }

    /// Only clips remember their framing.
    private func saveFraming() {
        guard let clip else { return }
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
                    MoveKeyframe(0.6)   // instant jump; a zero-length segment gives the next spring a NaN velocity
                    SpringKeyframe(1, duration: 0.25)
                    LinearKeyframe(1.35, duration: 0.45)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(1)   // instant jump; a zero-length segment gives the next spring a NaN velocity
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
            Button("Delete video") { deletingOriginal = item.original }
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

    /// Shows the top bar, then after 2.4s of playback fades it and slides the panel down to its grabber.
    private func wake() {
        chromeVisible = true
        idleTask?.cancel()
        idleTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled, model.isPlaying, !renaming else { return }
            chromeVisible = false
            withAnimation(reduceMotion ? .easeOut(duration: 0.4) : .spring(response: 0.6, dampingFraction: 0.85)) {
                panelHidden = true
            }
        }
    }
}

private struct FlashValues {
    var scale: Double = 0.6
    var opacity: Double = 0
}
