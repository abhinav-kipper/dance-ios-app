# Repaso — Sub-project C: Player extras, live previews, polish — Design

Date: 2026-10-16
Source brief: `~/Documents/UK_VISA_DOCS/repaso-handoff/HANDOFF.md` §4 (thumbnails), §5 (motion), §6.3 (Player), §7 (accessibility) + `design/Player.dc.html`
Builds on: sub-projects A (`2026-10-15-repaso-core-loop-design.md`) and B (`2026-10-16-repaso-drag-share-tags-design.md`), both shipped.

The user asked for C "the same way as B": no question round, decisions made by Claude and recorded here. Every choice below marked *(Claude's call)* is open to change.

## 1. Intent

C finishes the practice experience. A made a clip play instantly; C makes the player feel like a practice tool: flick between the clips of a folder, step through a move frame by frame, zoom in on footwork and have that framing remembered, send it to a TV. It also makes the library feel alive (muted moving previews) and does the last pass on motion, haptics and accessibility.

**Success criteria (C)**

1. Swiping up/down on the video moves to the next/previous clip of the queue. The video follows the finger at 55% and commits past 80pt. The new clip slides in from 120pt and starts playing at once. A right-edge indicator shows the position.
2. When paused, a horizontal drag steps frames (≈ 1 frame per 5pt) and a glass chip shows `Frame 0412`.
3. Pinching zooms 1–3×; one-finger drag pans while zoomed; the framing is saved per clip and restored next time that clip opens. The `1.6× Reset` chip or a two-finger tap resets it.
4. An AirPlay button sits in the top bar (swapped for the reset chip while zoomed).
5. Clip rows and original headers show muted, looping live previews of the clip's first ~3s, never more than 4 at a time, with poster fallback when scrolling fast, in Low Power Mode, or with Reduce Motion on.
6. Tap-to-pause still reacts with zero delay; no double-tap recognizer anywhere.
7. Reduce Motion: no overshoot, slides become fades, no live previews, no jiggle (already in B).
8. All core tests and the extended walkthrough pass on the iPhone 18 Pro simulator with zero build warnings. The A runtime warning about `AVAudioSession` on the main thread is gone, and the long-press-menu idle stall found in B is diagnosed and fixed (or documented if it's system behaviour).

**Non-goals:** landscape, playlists, mirror flip, iPad, editing clips from the player, saving speed per clip (speed stays global).
**Anti-goals:** anything that adds latency to tap-to-pause; previews that stutter scrolling or drain battery (hence the cap and the fallbacks).

## 2. Key decisions *(Claude's call)*

| Topic | Decision | Why |
|---|---|---|
| Gesture plumbing | SwiftUI `onTapGesture` (kept), one `DragGesture(minimumDistance: 6)` classified into swipe / scrub / pan, a simultaneous `MagnifyGesture`, and a two-finger tap through `UIGestureRecognizerRepresentable` | Keeps A's instant tap; SwiftUI has no touch-count tap |
| Gesture classification | Pure `PlayerGesture` in RepasoCore, values from the prototype | Testable without UI |
| Zoom storage | `Clip.zoom` (1…3) plus `panX`/`panY` stored as **fractions of the video view size**, clamped to ±(zoom−1)/2 | Survives device size changes; fields already exist in the model, so no migration |
| Zoom anchor | Scale around the view centre, then offset by pan | Simple and predictable; prototype used 50%/42%, which isn't noticeably different |
| Queue navigation | `PlayerView` holds a current index into `request.queue` (it was fixed in A); swipe changes it and reloads the same `PlayerModel` | One AVPlayer per screen stays (A rule) |
| Frame stepping | `AVPlayerItem.step(byCount:)` per 5pt; frame number = `round(currentTime × nominalFrameRate)` | Native, exact |
| AirPlay | `AVRoutePickerView` in a `UIViewRepresentable`, tinted white, active tint green | Standard control |
| Live preview engine | `AVQueuePlayer` + `AVPlayerLooper` over a time range, muted, `AVPlayerLayer` with `.resizeAspectFill` | Handoff choice; seamless loop |
| Live preview budget | A `PreviewBudget` (core, pure) of 4 slots, first-come by appearance, waiting list promoted on release | Handoff cap |
| Where previews run | Clip rows (46×32) and original headers (64×44). **Not** folder mosaics or pinned tiles. | A mosaic is 4 tiles: one card would eat the whole budget |
| Fast scrolling | Previews pause (poster shown) while the scroll view is `.decelerating` or `.animating` (`onScrollPhaseChange`), resume at `.idle`/`.tracking` | "Fast" = a flick; slow finger scrolling keeps them |
| Context-menu stall | Investigate first (Instruments-free: bisect with logs as in B); fix if ours | B left this open |

## 3. Core (`RepasoCore`)

### 3.1 PlayerGesture (pure)

```swift
public enum PlayerGesture {
    public enum Mode: Equatable { case pan, swipe, scrub }
    /// nil = not decided yet (keep listening). Order matters: pan when zoomed, then swipe, then scrub.
    public static func classify(dx: Double, dy: Double, isZoomed: Bool, isPlaying: Bool) -> Mode?
    //  isZoomed && hypot(dx,dy) > 6         → .pan
    //  |dy| > 14 && |dy| > |dx|             → .swipe
    //  !isPlaying && |dx| > 8               → .scrub
    public static let followFactor = 0.55          // video offset = dy × 0.55
    public static let commitDistance = 80.0
    /// +1 next (swipe up, dy < −80), −1 previous (dy > 80), 0 stay.
    public static func swipeDirection(dy: Double) -> Int
    public static let pointsPerFrame = 5.0
    /// Total frames to have stepped for a drag of `dx` (round toward zero).
    public static func frames(forDrag dx: Double) -> Int
}
```

### 3.2 Framing (pure) + LibraryService

```swift
public struct Framing: Equatable, Sendable {
    public var zoom: Double   // 1…3
    public var panX: Double   // fraction of view width
    public var panY: Double   // fraction of view height
    public static let identity: Framing
    public static let zoomRange: ClosedRange<Double> = 1...3
    /// Clamps zoom to 1…3 and pan to ±(zoom−1)/2; zoom ≤ 1.01 snaps to identity.
    public func clamped() -> Framing
    public var isZoomed: Bool        // zoom > 1.01
    public var label: String         // "1.6×"
}
extension Clip { public var framing: Framing }    // from zoom/panX/panY
// LibraryService
public func setFraming(_ clip: Clip, _ framing: Framing) throws   // stores framing.clamped(), saves
```

### 3.3 ClipQueue (pure)

`ClipQueue.step(from index: Int, by direction: Int, count: Int) -> Int?`: the neighbour index, or nil at either end (no wrap-around; the prototype stops at the ends).

### 3.4 PreviewBudget (pure)

```swift
public struct PreviewBudget<ID: Hashable> {
    public init(capacity: Int = 4)
    public private(set) var granted: [ID]    // in grant order
    public private(set) var waiting: [ID]    // FIFO
    public var isEnabled: Bool               // false → granted moves back to waiting front-first, nothing granted
    public mutating func request(_ id: ID)   // grant if room and enabled, else wait (no duplicates)
    public mutating func release(_ id: ID)   // drop from either list; promote waiting into free slots
    public mutating func setEnabled(_ on: Bool)   // re-enabling grants up to capacity from waiting
    public func isGranted(_ id: ID) -> Bool
}
```

### 3.5 Preview source + formatting

- `PreviewSource { id: UUID, fileName: String, range: ClosedRange<Double> }`, Sendable.
- `Clip.previewSource`: `start ... min(end, start + 3)`.
- `Original.previewSource`: from 30% of the video for 3s (clamped to duration).
- `TimeFormat.frame(_ n: Int) -> String` → `Frame 0412` (4 digits minimum, more if needed).

## 4. Player (app)

### 4.1 Queue and swipe

- `PlayerView` keeps `@State index` (starts at `request.index`). `clip` = `queue[index]`.
- Swipe mode: the video layer (and the flash/rest overlays) offset by `dy × 0.55`, opacity `1 − min(|offset|/260, 0.5)`. Release: `swipeDirection(dy)`; when non-zero and a neighbour exists → light haptic, `index` changes, the model loads the new clip, and the video enters from 120pt in the swipe direction with `Theme.spring` (fade under Reduce Motion). Otherwise it springs back to 0.
- On clip change: `markPlayed`, framing restored from the new clip, frame-step state cleared, chrome woken.
- Top pill text stays `<title> i / n`.
- **Page indicator:** right edge, vertically centred, 4pt-wide dots 6pt apart; the active one is 22pt tall and green, others 4pt tall at `white 40%`. Hidden when the queue has one clip. More than 9 clips: show a 9-dot window around the active one. Accessibility: hidden (the pill says the position); the video element gets `accessibilityAdjustableAction` (increment = next clip, decrement = previous) as the VoiceOver alternative to swiping.

### 4.2 Frame stepping

- Scrub mode (paused only): `target = frames(forDrag: dx)`; the model steps by `target − stepped` and records it. Selection haptic per step (rate-limited by the step itself).
- Chip (glass capsule, centred above the panel from the first step until playback resumes or the clip changes, so the frame number stays readable while paused): `chevron.left` · `Frame 0412` (mono 15) · `chevron.right`.
- `PlayerModel.frameIndex` is computed from `currentTime` and the asset's `nominalFrameRate` (loaded at `load`, default 30).
- Playing again resumes from the stepped position (not the clip start) unless at the end.

### 4.3 Zoom and pan

- `MagnifyGesture` simultaneous with the drag: `live = (base.zoom × magnification)` clamped; pan mode updates `live.pan = base.pan + translation / viewSize`, clamped.
- Applied to the video layer as `.scaleEffect(zoom).offset(x: panX·w, y: panY·h)` inside a clipped container; animates with `Theme.spring` only when not under a finger.
- Gesture end → `setFraming(clip, live.clamped())` (one save per gesture).
- Two-finger tap (`UITapGestureRecognizer`, `numberOfTouchesRequired = 2`, through `UIGestureRecognizerRepresentable`) → reset to identity, save.
- Top bar trailing slot: when zoomed, a glass chip `1.6× Reset` (label "Reset zoom"); otherwise the AirPlay button (label "AirPlay").

### 4.4 AirPlay

`AirPlayButton: UIViewRepresentable` wrapping `AVRoutePickerView` (44×44, `tintColor` white, `activeTintColor` accent, `prioritizesVideoDevices = true`), inside the same glass circle as the close button. `AVPlayer.allowsExternalPlayback` stays true (default).

### 4.5 Audio session fix

Move `setCategory` into the same detached task as `setActive`; that silences the "can lead to UI unresponsiveness" runtime warning from A.

## 5. Live previews (app)

- `PreviewCoordinator` (`@Observable @MainActor`, in `AppEnvironment`): wraps `PreviewBudget<UUID>`; `isEnabled = !lowPower && !reduceMotion && !scrollingFast && !uiTestsDisabled`. Observes `NSProcessInfoPowerStateDidChange`. Screens report scroll phase via `env.previews.setScrolling(fast:)`.
- `LivePreviewView(source:)`: owns an `AVQueuePlayer` + `AVPlayerLooper(templateItem: AVPlayerItem(asset), timeRange:)`, `isMuted = true`, `preventsDisplaySleepDuringVideoPlayback = false`, layer `.resizeAspectFill`. Created when granted, torn down when the grant goes away (no paused players kept around).
- `PosterView` gains `live: PreviewSource? = nil`. When set: on appear `request(id)`, on disappear `release(id)`. While granted, the live view fades in over the poster once the player is `readyToPlay` (0.25s), so there's never a black flash.
- Used by `ClipRow` (clip.previewSource) and the `OriginalCard` header (original.previewSource).
- **Launch arg `-noLivePreviews`** disables them for UI tests that need the app to go idle; the walkthrough keeps them on unless that proves flaky.

## 6. Polish

- **Haptics:** light impact on swipe commit; selection on each frame step; light impact on zoom reset; (B already: drop success, spring-load).
- **Reduce Motion audit:** go through every `Theme.spring` use and every transition added in A–C; under Reduce Motion use `.easeOut(0.2)` and opacity transitions. Add a `Theme.motion(_ reduceMotion: Bool) -> Animation` helper and use it at those sites rather than repeating the ternary.
- **Context-menu idle stall (diagnosed):** caused by the system when one view has both `.draggable` and `.contextMenu`. A bare `.draggable` on the clip row reproduces it with all Repaso drag code removed (≈133s vs 16s for the same steps). While the menu is open the app never reports idle to XCUITest, so each following step waits out the 60s timeout. No user-visible effect; kept, since dragging clips onto folders needs both. Documented in the walkthrough.
- **Accessibility:** labels for the new controls (`Reset zoom`, `AirPlay`, `Frame 412` value on the chip); the adjustable action on the video for next/previous.

## 7. Error handling

| Failure | Behaviour |
|---|---|
| Next clip's video file missing | Same "Video file missing" card as A, swipes still work |
| `step(byCount:)` unsupported (`canStepForward == false`) | Scrub mode does nothing; no chip |
| Live preview asset fails to load | Poster stays; the slot is released |
| `setFraming` save fails | `Couldn't save` toast (A's `env.perform`); the on-screen zoom stays |
| Route picker unavailable (simulator) | Button still shows; the system sheet says no devices |

## 8. Testing

**Core (Swift Testing):** `PlayerGesture.classify` (each mode, priority, undecided), `swipeDirection` thresholds, `frames(forDrag:)` rounding and sign; `Framing.clamped` (zoom range, pan limits per zoom, snap to identity), `label`; `setFraming` persists clamped values; `ClipQueue.step` ends; `PreviewBudget` (cap 4, FIFO waiting, release promotes, disable/enable, no duplicates); `previewSource` ranges; `TimeFormat.frame`.

**UI (XCUITest, seeded):** extend the walkthrough's Player step: swipe up → pill reads `Turns 2 / 3`; swipe down → back to `1 / 3`; pinch out (`pinch(withScale: 2, velocity: 1)`) → `Reset zoom` exists → tap it → `AirPlay` exists again; tap to pause, drag horizontally → a `Frame` chip exists. Screenshots of each.

**Manual (device):** AirPlay to a TV, live previews scrolling 200+ clips, Low Power Mode fallback, haptics feel.

## 9. Out of scope (C)

Per-clip speed, mirror flip, slow-motion export, landscape, playlist building, remembering playback position.
