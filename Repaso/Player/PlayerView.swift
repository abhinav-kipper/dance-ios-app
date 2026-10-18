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
    @State private var librarySheet: LibrarySheet?
    @State private var cutting: CutRequest?
    @State private var fullVideo: PlayerRequest?
    @State private var confirmingDelete = false
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
    /// Studying frames (tap or hold a side, or drag sideways while paused): controls stay out of the way.
    @State private var stepping = false
    // Timeline scrubbing
    @State private var scrubbing = false
    // Cover shown while the next item's first frame loads (no black flash on swipe)
    @State private var startFrames = StartFrames()
    @State private var cover: CGImage?
    @State private var coverTimeout: Task<Void, Never>?
    // Zoom and pan
    @State private var framing = Framing.identity
    @State private var baseFraming = Framing.identity
    @State private var isPinching = false
    /// A pinch began during the current one-finger drag, so that drag must not swipe, scrub or pan.
    @State private var dragHadPinch = false
    @State private var isDragging = false
    /// A swipe from the left edge: the Player follows the finger and closes like going back.
    @State private var edgeDrag: CGFloat?
    @State private var videoSize = CGSize(width: 1, height: 1)
    @State private var resets = 0
    // Hold to seek
    @State private var holdEndedAt: Date?
    // Sliding panel
    @State private var panelHidden = false
    @State private var panelHeight: CGFloat = 0
    @State private var panelDrag: CGFloat = 0
    @State private var safeBottom: CGFloat = 0
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
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { safeBottom = $0 }
            Group {
                if model.missingFile {
                    missingFileCard
                } else {
                    video
                }
                flashOverlay
                if let seconds = model.restingSeconds { restRing(seconds) }
            }
            .offset(x: edgeDrag ?? 0, y: swipeOffset + entryOffset)
            .opacity(entryOpacity * (1 - min(abs(swipeOffset) / 260, 0.5)))
            VStack {
                ZStack(alignment: .top) {
                    topBar
                    if showFrameChip {
                        // Small and up top, where the top bar was: the dancer's body and feet stay clear.
                        StepChip(position: model.positionInItem, length: model.itemLength,
                                 direction: model.lastStepDirection, tick: model.frameIndex)
                            .padding(.top, 18)
                            .transition(.opacity)
                    }
                }
                Spacer()
                panel
            }
            .animation(.easeOut(duration: 0.2), value: showFrameChip)
            .overlay(alignment: .bottom) { peekGrabber }
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
        .defersSystemGestures(on: .bottom)   // dragging the grabber up mustn't go Home
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            model.speed = speed
            loadCurrentClip()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            idleTask?.cancel()
            coverTimeout?.cancel()
            model.tearDown()
        }
        .onChange(of: speed) { _, new in model.speed = new }
        .onChange(of: model.isPlaying) { _, playing in
            if playing {
                showFrameChip = false
                stepping = false
            } else if !stepping {
                showPanel()   // paused with a tap: controls come back; paused by stepping: they stay away
            }
            if !stepping { wake() }
        }
        .onChange(of: model.frameIndex) { _, _ in
            if model.holdZone != .none { steps += 1 }   // a light tick per frame while holding
        }
        .sheet(item: $sharing) { ShareSheet(clip: $0) }
        .sheet(item: $librarySheet) { $0.content }
        .fullScreenCover(item: $cutting, onDismiss: { loadCurrentClip() }) {   // reload: the trim may have changed the range
            CutView(original: $0.original, focusClipID: $0.focusClipID)
        }
        .fullScreenCover(item: $fullVideo) { PlayerView(request: $0) }
        .confirmationDialog("Delete this clip?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete clip", role: .destructive, action: deleteCurrentClip)
        } message: {
            Text("The video stays in your library.")
        }
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
                Text(scrubbing ? TimeFormat.precise(model.positionInItem) : TimeFormat.duration(item.length))
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
            scrubber
            SpeedControl(speed: $speed, onChange: wake)
            HStack(spacing: 8) {
                loopButton
                gapButton
                Spacer(minLength: 4)
                if let clip {
                    favoriteButton(clip)
                    learnedButton(clip)
                }
                moreMenu
            }
        }
        .padding(.init(top: 6, leading: 16, bottom: 14, trailing: 16))
        .panelGlass(radius: Theme.Radius.panel)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
        .offset(y: panelOffset)
        .opacity(panelOpacity)
        .allowsHitTesting(!panelHidden)
        .accessibilityHidden(panelHidden)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring, value: panelHidden)
        .animation(.easeOut(duration: 0.6), value: chromeVisible)
        .simultaneousGesture(TapGesture().onEnded { wake() })
    }

    /// Slid away = entirely below the screen; only the separate peek grabber stays. A drag follows the finger.
    private var panelOffset: CGFloat {
        let hiddenOffset = reduceMotion ? 0 : panelHeight + 12 + safeBottom
        return max(0, (panelHidden ? hiddenOffset : 0) + panelDrag)
    }

    private var panelOpacity: Double {
        if panelHidden {
            // Fades in as it is dragged up from the bottom edge.
            return reduceMotion ? 0 : min(1, Double(max(0, -panelDrag)) / 80)
        }
        return chromeVisible || !model.isPlaying ? 1 : 0.42
    }

    /// The grabber at the top of the open panel: drag it down (or tap) to send the panel away.
    private var grabber: some View {
        Capsule()
            .fill(.white.opacity(0.5))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape([.interaction, .accessibility], Rectangle())
            .gesture(grabberDrag)
            .onTapGesture { setPanelHidden(true) }
            .accessibilityLabel("Hide controls")
            .accessibilityAddTraits(.isButton)
    }

    /// All that shows of the panel while it is away: a slim handle at the bottom edge. Drag it up (or tap) to bring the panel back.
    private var peekGrabber: some View {
        Color.clear
            .frame(width: 140, height: 34)
            .overlay {
                Capsule()
                    .fill(.white.opacity(0.55))
                    .frame(width: 40, height: 5)
                    .shadow(color: .black.opacity(0.45), radius: 2)
                    .opacity(panelHidden && panelDrag == 0 ? 1 : 0)
            }
            .contentShape([.interaction, .accessibility], Rectangle())
            .gesture(grabberDrag)
            .onTapGesture { setPanelHidden(false) }
            .padding(.bottom, 2)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(panelHidden)
            .accessibilityHidden(!panelHidden)
            .accessibilityLabel("Show controls")
            .accessibilityAddTraits(.isButton)
            .animation(.easeOut(duration: 0.2), value: panelHidden)
    }

    private var grabberDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                panelDrag = panelHidden ? min(0, value.translation.height) : max(0, value.translation.height)
            }
            .onEnded { value in
                let dy = value.predictedEndTranslation.height
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring) {
                    if panelHidden && dy < -30 { panelHidden = false }
                    else if !panelHidden && dy > 40 { panelHidden = true }
                    panelDrag = 0
                }
                if !panelHidden { wake() }
            }
    }

    private func setPanelHidden(_ hidden: Bool) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring) { panelHidden = hidden }
        if !hidden { wake() }
    }

    /// The timeline: a slim line that can be tapped or dragged anywhere to move through the clip, like Cut's strip.
    private var scrubber: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let x = width * model.progress
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(.white).frame(width: x.isFinite ? x : 0)
            }
            .frame(height: scrubbing ? 6 : 3)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .offset(x: (x.isFinite ? x : 0) - 7)
                    .opacity(scrubbing ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !scrubbing {
                            scrubbing = true
                            model.beginScrub()
                        }
                        model.scrub(to: value.location.x / width)
                        wake()
                    }
                    .onEnded { value in
                        model.scrub(to: value.location.x / width)
                        model.endScrub()
                        scrubbing = false
                        wake()
                    }
            )
        }
        .frame(height: 40)
        .padding(.vertical, -14)   // a tall touch area without taking room in the panel
        .animation(.easeOut(duration: 0.15), value: scrubbing)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(TimeFormat.precise(model.positionInItem)) of \(TimeFormat.precise(model.itemLength))")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? 0.05 : -0.05
            model.beginScrub()
            model.scrub(to: model.progress + delta)
            model.endScrub()
        }
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
                .onTapGesture { startRenaming() }
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

    // MARK: Clip buttons

    private func favoriteButton(_ clip: Clip) -> some View {
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

    private func learnedButton(_ clip: Clip) -> some View {
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

    /// Everything you can do to the clip or video without leaving the Player.
    private var moreMenu: some View {
        Menu {
            if let clip {
                Button("Name & note…", systemImage: "pencil") { librarySheet = .info(clip) }
                Button("Trim…", systemImage: "timeline.selection") {
                    guard let original = clip.original else { return }
                    model.pause()
                    cutting = CutRequest(original: original, focusClipID: clip.id)
                }
                if let original = clip.original, !original.isClipSource {
                    Button("Play full video", systemImage: "film") {
                        model.pause()
                        fullVideo = PlayerRequest(items: [.original(original)], index: 0, title: original.title)
                    }
                }
                Divider()
                Button("Move to folder…", systemImage: "folder") { librarySheet = .move(.clip(clip)) }
                Button("Add to folders…", systemImage: "folder.badge.plus") { librarySheet = .link(.clip(clip)) }
                Button("Share", systemImage: "square.and.arrow.up") {
                    model.pause()
                    sharing = clip
                }
                Divider()
                Button("Delete clip", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            } else if let original = item.original {
                Button("Edit details…", systemImage: "pencil") { librarySheet = .videoInfo(original) }
                Button("Move to folder…", systemImage: "folder") { librarySheet = .move(.original(original)) }
                Button("Add to folders…", systemImage: "folder.badge.plus") { librarySheet = .link(.original(original)) }
                Divider()
                Button("Delete video", systemImage: "trash", role: .destructive) { deletingOriginal = original }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.15), in: Circle())
                .contentShape([.interaction, .accessibility], Circle())
        }
        .menuStyle(.button)
        .buttonStyle(PressableButtonStyle())
        // Keep the panel where it is while the menu is open: sliding it away underneath would move or close the menu.
        .simultaneousGesture(TapGesture().onEnded { idleTask?.cancel() })
        .accessibilityLabel("More actions")
    }

    private func startRenaming() {
        guard clip != nil else { return }
        nameDraft = ""   // empty: typing replaces the name; return with nothing keeps it
        renaming = true
        nameFocused = true
        showPanel()
    }

    /// Closes the Player first: the clip must not be on screen when it is deleted.
    private func deleteCurrentClip() {
        guard let clip else { return }
        let env = env
        let ctx = ctx
        dismiss()
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            env.perform { try env.library(ctx).deleteClip(clip) }
        }
    }

    // MARK: Video and gestures

    private var video: some View {
        ZStack {
            PlayerLayerView(player: model.player) { ready in
                if ready { clearCover() }
            }
            if let cover {
                Image(decorative: cover, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            }
        }
            .scaleEffect(framing.zoom)
            .offset(x: framing.panX * videoSize.width, y: framing.panY * videoSize.height)
            .clipped()
            .ignoresSafeArea()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { videoSize = $0 }
            .animation(isPinching || gestureMode == .pan ? nil : Theme.motion(reduceMotion), value: framing)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                // A long press also ends with a lift; that lift isn't a tap.
                if let ended = holdEndedAt, Date.now.timeIntervalSince(ended) < 0.4 { return }
                guard model.holdZone == .none else { return }
                // Left third: back one frame; right third: forward one frame; centre: play/pause.
                let step = HoldSeek.frameStep(for: HoldSeek.zone(forX: location.x, width: videoSize.width))
                if step != 0, model.canStep {
                    enterStepping()
                    model.step(by: step)
                    steps += 1
                    showChip()
                    return
                }
                model.togglePlay()
                flash += 1
                wake()
            }
            .gesture(HoldSeekGesture(onBegin: { zone in
                guard !isPinching, gestureMode == nil, HoldSeek.frameStep(for: zone) != 0, model.canStep else { return }
                enterStepping()
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
            .accessibilityAction(named: "Next frame") { accessibleStep(1) }
            .accessibilityAction(named: "Previous frame") { accessibleStep(-1) }
    }

    private func accessibleStep(_ count: Int) {
        guard model.canStep else { return }
        enterStepping()
        model.step(by: count)
        showChip()
    }

    /// Frame study: the top bar and panel get out of the way and stay away until playback resumes.
    private func enterStepping() {
        stepping = true
        idleTask?.cancel()
        chromeVisible = false
        renaming = false
        guard !panelHidden else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.5, dampingFraction: 0.85)) {
            panelHidden = true
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
                // From the left edge, a rightward swipe goes back, as everywhere else on iPhone.
                if edgeDrag != nil || (gestureMode == nil && value.startLocation.x < 28 && dx > 10 && dx > abs(dy)) {
                    edgeDrag = max(0, dx)
                    return
                }
                if gestureMode == nil {
                    gestureMode = PlayerGesture.classify(dx: dx, dy: dy, isZoomed: framing.isZoomed, isPlaying: model.isPlaying)
                    if gestureMode == .pan { baseFraming = framing }
                    if gestureMode == .scrub && !model.canStep { gestureMode = nil }
                    if gestureMode == .scrub { enterStepping() }
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
                if gestureMode != .scrub { wake() }
            }
            .onEnded { value in
                if let edge = edgeDrag {
                    isDragging = false
                    if edge > 110 || value.predictedEndTranslation.width > 260 {
                        dismiss()
                    } else {
                        withAnimation(Theme.motion(reduceMotion)) { edgeDrag = nil }
                    }
                    return
                }
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
                case nil:
                    // A quick flick can arrive with no move events in between: judge it by where it ended.
                    let dx = value.translation.width, dy = value.translation.height
                    if !isPinching, PlayerGesture.classify(dx: dx, dy: dy, isZoomed: framing.isZoomed,
                                                           isPlaying: model.isPlaying) == .swipe {
                        finishSwipe(dy: dy)
                    }
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
        stepping = false
        renaming = false
        showCover()
        model.load(item, videos: env.videos)
        prefetchNeighbours()
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

    // MARK: Swipe cover

    /// Puts the new item's first frame (decoded ahead) over the player until the player has drawn it.
    private func showCover() {
        cover = startFrames.images[StartFrames.key(item)]
        coverTimeout?.cancel()
        guard cover != nil else { return }
        coverTimeout = Task {
            try? await Task.sleep(for: .seconds(1.5))   // never leave a still frame up if the layer doesn't report
            guard !Task.isCancelled else { return }
            clearCover()
        }
    }

    private func clearCover() {
        guard cover != nil else { return }
        coverTimeout?.cancel()
        withAnimation(.easeOut(duration: 0.12)) { cover = nil }
    }

    private func prefetchNeighbours() {
        let items = request.items
        let nearby = [index - 1, index, index + 1].filter { items.indices.contains($0) }.map { items[$0] }
        startFrames.prefetch(nearby, videos: env.videos)
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
