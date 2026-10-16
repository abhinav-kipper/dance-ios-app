# Repaso Sub-project C (Player extras, Live previews, Polish) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swipe between clips, frame stepping, per-clip zoom memory, AirPlay, muted live previews (max 4), and a motion/haptics/accessibility polish pass.

**Architecture:** Gesture maths, framing, queue stepping and the preview budget are pure types in `RepasoCore` with Swift Testing tests; `LibraryService.setFraming` persists zoom. The app wires them into `PlayerView`/`PlayerModel`, a new `PreviewCoordinator` + `LivePreviewView`, and an `AirPlayButton`.

**Tech Stack:** SwiftUI (iOS 26+, Xcode 27), SwiftData, AVFoundation (`step(byCount:)`, `AVPlayerLooper`), AVKit (`AVRoutePickerView`), UIKit gesture bridge (`UIGestureRecognizerRepresentable`), Swift Testing, XCUITest.

**Spec:** `docs/superpowers/specs/2026-10-16-repaso-player-previews-polish-design.md`

## Global Constraints

- Deployment target iOS 26.0; Swift 6, strict concurrency complete; zero build warnings.
- Prefix every tool command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; destination `platform=iOS Simulator,name=iPhone 18 Pro`.
- Tap on the video stays a plain single tap: no double-tap recognizer anywhere.
- Gesture values: pan > 6pt when zoomed; swipe when |dy| > 14 and |dy| > |dx|; scrub when paused and |dx| > 8; follow 0.55; commit 80pt; slide-in 120pt; 5pt per frame; zoom 1…3.
- Live previews: max 4 simultaneous, first ~3s of the clip, muted, off in Low Power Mode, under Reduce Motion, while flick-scrolling, and with `-noLivePreviews`.
- All mutations through `LibraryService`. No commits unless the user asks.

## Review Focus

1. Swiping past the first/last clip must spring back, not crash or wrap. → `ClipQueue` tests (Task 1).
2. A pan saved at 3× must not leave the video off-screen when reopened. → `Framing.clamped` tests (Task 1).
3. Leaving a screen must release preview slots, or previews stop appearing. → `PreviewBudget` release/promote tests (Task 1) + `onDisappear` release (Task 4).
4. Frame stepping at the clip's first frame must not step before `clip.start`. → model clamps (Task 2, manual).
5. Live previews must not keep the app non-idle in UI tests. → `-noLivePreviews` switch (Task 4); walkthrough run (Task 6).

---

### Task 1: Core — PlayerGesture, Framing + setFraming, ClipQueue, PreviewBudget, PreviewSource, TimeFormat.frame

**Files:**
- Create: `Packages/RepasoCore/Sources/RepasoCore/Playback/PlayerGesture.swift`, `Playback/Framing.swift`, `Playback/ClipQueue.swift`, `Preview/PreviewBudget.swift`, `Preview/PreviewSource.swift`
- Modify: `Library/LibraryService.swift` (`setFraming`), `Format/TimeFormat.swift` (`frame`)
- Test: `Packages/RepasoCore/Tests/RepasoCoreTests/PlayerExtrasTests.swift`

**Interfaces (produces):** `PlayerGesture.classify(dx:dy:isZoomed:isPlaying:) -> Mode?`, `.swipeDirection(dy:) -> Int`, `.frames(forDrag:) -> Int`, constants; `Framing` (`zoom`, `panX`, `panY`, `identity`, `clamped()`, `isZoomed`, `label`), `Clip.framing`; `LibraryService.setFraming(_:_:)`; `ClipQueue.step(from:by:count:) -> Int?`; `PreviewBudget<ID>`; `PreviewSource`, `Clip.previewSource`, `Original.previewSource`; `TimeFormat.frame(_:)`.

- [ ] **Step 1: Failing tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import RepasoCore

struct PlayerGestureTests {
    @Test func classifiesByPriority() {
        #expect(PlayerGesture.classify(dx: 5, dy: 5, isZoomed: true, isPlaying: true) == .pan)
        #expect(PlayerGesture.classify(dx: 3, dy: -20, isZoomed: false, isPlaying: true) == .swipe)
        #expect(PlayerGesture.classify(dx: 12, dy: 2, isZoomed: false, isPlaying: false) == .scrub)
        #expect(PlayerGesture.classify(dx: 12, dy: 2, isZoomed: false, isPlaying: true) == nil)
        #expect(PlayerGesture.classify(dx: 2, dy: 10, isZoomed: false, isPlaying: false) == nil)
    }
    @Test func swipeCommitsPast80() {
        #expect(PlayerGesture.swipeDirection(dy: -81) == 1)
        #expect(PlayerGesture.swipeDirection(dy: 81) == -1)
        #expect(PlayerGesture.swipeDirection(dy: -79) == 0)
    }
    @Test func framesPerFivePoints() {
        #expect(PlayerGesture.frames(forDrag: 12) == 2)
        #expect(PlayerGesture.frames(forDrag: -12) == -2)
        #expect(PlayerGesture.frames(forDrag: 4) == 0)
    }
    @Test func queueStopsAtEnds() {
        #expect(ClipQueue.step(from: 0, by: 1, count: 3) == 1)
        #expect(ClipQueue.step(from: 2, by: 1, count: 3) == nil)
        #expect(ClipQueue.step(from: 0, by: -1, count: 3) == nil)
    }
    @Test func frameLabel() {
        #expect(TimeFormat.frame(412) == "Frame 0412")
        #expect(TimeFormat.frame(12345) == "Frame 12345")
    }
}

struct FramingTests {
    @Test func clampsZoomAndPan() {
        let f = Framing(zoom: 5, panX: 3, panY: -3).clamped()
        #expect(f.zoom == 3)
        #expect(f.panX == 1)
        #expect(f.panY == -1)
        #expect(Framing(zoom: 2, panX: 0.8, panY: 0).clamped().panX == 0.5)
    }
    @Test func nearOneSnapsToIdentity() {
        #expect(Framing(zoom: 1.005, panX: 0.2, panY: 0.1).clamped() == .identity)
        #expect(!Framing.identity.isZoomed)
        #expect(Framing(zoom: 1.6, panX: 0, panY: 0).label == "1.6×")
    }
}

struct PreviewBudgetTests {
    @Test func capsAndPromotes() {
        var b = PreviewBudget<Int>(capacity: 2)
        for i in 1...3 { b.request(i) }
        b.request(1)
        #expect(b.granted == [1, 2])
        #expect(b.waiting == [3])
        b.release(1)
        #expect(b.granted == [2, 3])
        #expect(b.waiting.isEmpty)
    }
    @Test func disableParksAndReenableGrants() {
        var b = PreviewBudget<Int>(capacity: 2)
        b.request(1); b.request(2); b.request(3)
        b.setEnabled(false)
        #expect(b.granted.isEmpty)
        #expect(b.waiting == [1, 2, 3])
        b.request(4)
        #expect(b.granted.isEmpty)
        b.setEnabled(true)
        #expect(b.granted == [1, 2])
        #expect(b.isGranted(2) && !b.isGranted(3))
    }
}

@MainActor
struct FramingLibraryTests {
    @Test func setFramingPersistsClamped() throws {
        let ctx = try makeContext()
        let lib = LibraryService(context: ctx)
        let o = try lib.addOriginal(title: "T", fileName: "t.mov", duration: 100, recordedAt: nil, to: nil)
        let c = try lib.addClip(to: o, start: 10, end: 20)
        try lib.setFraming(c, Framing(zoom: 4, panX: 2, panY: 0))
        #expect(c.framing == Framing(zoom: 3, panX: 1, panY: 0))
        #expect(c.previewSource?.range == 10...13)
        #expect(o.previewSource.range == 30...33)
    }
}
```

- [ ] **Step 2: Run** `xcodebuild test … -only-testing:RepasoCoreTests` → compile failure.
- [ ] **Step 3: Implement** (code below), **Step 4:** run → all pass.

```swift
// PlayerGesture.swift
import Foundation

/// How a one-finger drag on the player video is read (values from the Player prototype).
public enum PlayerGesture {
    public enum Mode: Equatable, Sendable { case pan, swipe, scrub }

    public static let followFactor = 0.55
    public static let commitDistance = 80.0
    public static let slideInDistance = 120.0
    public static let pointsPerFrame = 5.0

    /// nil = not decided yet. Pan wins when zoomed, then a mostly-vertical swipe, then a paused scrub.
    public static func classify(dx: Double, dy: Double, isZoomed: Bool, isPlaying: Bool) -> Mode? {
        if isZoomed && hypot(dx, dy) > 6 { return .pan }
        if abs(dy) > 14 && abs(dy) > abs(dx) { return .swipe }
        if !isPlaying && abs(dx) > 8 { return .scrub }
        return nil
    }

    /// +1 = next clip (swipe up), −1 = previous, 0 = stay.
    public static func swipeDirection(dy: Double) -> Int {
        dy < -commitDistance ? 1 : dy > commitDistance ? -1 : 0
    }

    public static func frames(forDrag dx: Double) -> Int {
        Int((dx / pointsPerFrame).rounded(.towardZero))
    }
}
```

```swift
// Framing.swift
import Foundation

/// A clip's remembered zoom and pan. Pan is a fraction of the video view's size, so it survives device changes.
public struct Framing: Equatable, Sendable {
    public var zoom: Double
    public var panX: Double
    public var panY: Double

    public static let identity = Framing(zoom: 1, panX: 0, panY: 0)
    public static let zoomRange: ClosedRange<Double> = 1...3

    public init(zoom: Double, panX: Double, panY: Double) {
        self.zoom = zoom
        self.panX = panX
        self.panY = panY
    }

    /// Zoom within 1…3, pan within ±(zoom−1)/2 so the video always covers the view; ~1× snaps to identity.
    public func clamped() -> Framing {
        let z = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        guard z > 1.01 else { return .identity }
        let limit = (z - 1) / 2
        return Framing(zoom: z, panX: min(max(panX, -limit), limit), panY: min(max(panY, -limit), limit))
    }

    public var isZoomed: Bool { zoom > 1.01 }

    public var label: String { String(format: "%.1f×", zoom) }
}

extension Clip {
    public var framing: Framing { Framing(zoom: zoom, panX: panX, panY: panY) }
}
```

```swift
// ClipQueue.swift
public enum ClipQueue {
    /// The neighbouring index, or nil past either end (no wrap-around).
    public static func step(from index: Int, by direction: Int, count: Int) -> Int? {
        let next = index + direction
        return direction != 0 && (0..<count).contains(next) ? next : nil
    }
}
```

```swift
// PreviewBudget.swift
/// Hands out a fixed number of live-preview slots; the rest wait in arrival order.
public struct PreviewBudget<ID: Hashable> {
    public let capacity: Int
    public private(set) var granted: [ID] = []
    public private(set) var waiting: [ID] = []
    public private(set) var isEnabled = true

    public init(capacity: Int = 4) { self.capacity = capacity }

    public func isGranted(_ id: ID) -> Bool { granted.contains(id) }

    public mutating func request(_ id: ID) {
        guard !granted.contains(id), !waiting.contains(id) else { return }
        waiting.append(id)
        fill()
    }

    public mutating func release(_ id: ID) {
        granted.removeAll { $0 == id }
        waiting.removeAll { $0 == id }
        fill()
    }

    /// Disabling parks every granted id at the front of the queue, so re-enabling restores the same previews.
    public mutating func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if !on {
            waiting = granted + waiting
            granted = []
        }
        fill()
    }

    private mutating func fill() {
        guard isEnabled else { return }
        while granted.count < capacity, !waiting.isEmpty { granted.append(waiting.removeFirst()) }
    }
}
```

```swift
// PreviewSource.swift
import Foundation

/// What a muted live preview loops: a short range of an original's file.
public struct PreviewSource: Hashable, Sendable {
    public static let length = 3.0
    public let id: UUID
    public let fileName: String
    public let range: ClosedRange<Double>

    public init(id: UUID, fileName: String, range: ClosedRange<Double>) {
        self.id = id
        self.fileName = fileName
        self.range = range
    }
}

extension Clip {
    public var previewSource: PreviewSource? {
        guard let original else { return nil }
        return PreviewSource(id: id, fileName: original.fileName, range: start...min(end, start + PreviewSource.length))
    }
}

extension Original {
    public var previewSource: PreviewSource {
        let start = duration * 0.3
        return PreviewSource(id: id, fileName: fileName, range: start...min(duration, start + PreviewSource.length))
    }
}
```

`LibraryService` (Clips section):

```swift
public func setFraming(_ clip: Clip, _ framing: Framing) throws {
    let f = framing.clamped()
    clip.zoom = f.zoom
    clip.panX = f.panX
    clip.panY = f.panY
    try save()
}
```

`TimeFormat`:

```swift
/// "Frame 0412" for the paused frame-stepping chip.
public static func frame(_ index: Int) -> String {
    "Frame " + String(format: "%04d", max(0, index))
}
```

---

### Task 2: Player — queue swipe, page indicator, frame stepping, audio session fix

**Files:** Modify `Repaso/Player/PlayerModel.swift`, `Repaso/Player/PlayerView.swift`; Create `Repaso/Player/PageIndicator.swift`, `Repaso/Player/FrameChip.swift`.

- `PlayerModel`: `setCategory` moves into the detached task; adds `frameRate` (loaded from the video track's `nominalFrameRate`, default 30), `frameIndex` (from `currentTime`), `canStep`, `step(by:)` (pauses, clamps to the clip range using the item's current time, calls `currentItem.step(byCount:)`).
- `PlayerView`: `@State index`; `clip` = `request.queue[index]`; one `DragGesture(minimumDistance: 6)` simultaneous with the existing tap, classified once per gesture with `PlayerGesture.classify`; swipe offsets the video, commits with `ClipQueue.step`, then `load` + `markPlayed`, an `entry` offset of ±120 springs to 0 (fade under Reduce Motion); `.sensoryFeedback(.impact(weight: .light), trigger: index)`. Scrub steps `frames(forDrag:) − stepped`, `.sensoryFeedback(.selection, trigger: frameIndex)`; `FrameChip` shows while scrubbing and 1.2s after. `PageIndicator(count:index:)` on the right edge. Video gets `accessibilityAdjustableAction` for next/previous.

### Task 3: Player — pinch zoom, pan, two-finger reset, AirPlay

**Files:** Create `Repaso/Player/AirPlayButton.swift`, `Repaso/Player/TwoFingerTap.swift`; Modify `PlayerView.swift`.

- `@State framing` (live) + `baseFraming` (gesture start); `MagnifyGesture` simultaneous: `framing.zoom = base.zoom × magnification` clamped; pan mode: `base.pan + translation / size`; both through `.clamped()`; on end `env.perform { try lib.setFraming(clip, framing) }`.
- Video: `.scaleEffect(framing.zoom).offset(x: framing.panX·w, y: framing.panY·h)` in a `GeometryReader`, `.clipped()`.
- `TwoFingerTap: UIGestureRecognizerRepresentable` (`UITapGestureRecognizer`, 2 touches) → reset + save + light haptic.
- Top bar trailing: zoomed → glass chip `"\(framing.label) Reset"` (label "Reset zoom"); else `AirPlayButton` (label "AirPlay").

### Task 4: Live previews

**Files:** Create `Repaso/Components/LivePreviewView.swift`, `Repaso/App/PreviewCoordinator.swift`; Modify `AppEnvironment.swift` (`let previews = PreviewCoordinator()`), `PosterView.swift` (`live:`), `ClipRow.swift`, `OriginalCard.swift`, `FolderView.swift` + `HomeView.swift` + `FavoritesView` (`onScrollPhaseChange` → `env.previews.setScrolling`).

- `PreviewCoordinator`: `budget: PreviewBudget<UUID>`; `request/release/isGranted`; `setScrolling(fast:)`, Low Power observer, `reduceMotion` set from the root view, `-noLivePreviews` arg → recompute `budget.setEnabled`.
- `LivePreviewView`: `UIViewRepresentable` with an `AVPlayerLayer` (`.resizeAspectFill`); a `@MainActor` `LoopingPreview` object creates `AVQueuePlayer` + `AVPlayerLooper(player:templateItem:timeRange:)`, muted, `play()`; reports ready via `AVPlayerLayer.isReadyForDisplay` KVO → fade in.
- `PosterView(request:, live: PreviewSource?)`: request on appear, release on disappear; overlay `LivePreviewView` when granted.

### Task 5: Polish

- `Theme.motion(_ reduceMotion: Bool, _ animation: Animation = Theme.spring) -> Animation` and use it at the Reduce-Motion sites.
- Context-menu idle stall: reproduce with logs (long press a clip row in the walkthrough), fix if ours.
- Labels: `Reset zoom`, `AirPlay`, `Frame N` value; adjustable action.

### Task 6: Walkthrough + verification

In `testCoreLoopWalkthrough` after `04-player-slow`, before `close.tap()`:

```swift
// Swipe to the next clip and back
let video = app.otherElements["Video"]
video.swipeUp()
XCTAssertTrue(app.staticTexts["Turns 2 / 3"].waitForExistence(timeout: 3))
snap("04b-player-next")
video.swipeDown()
XCTAssertTrue(app.staticTexts["Turns 1 / 3"].waitForExistence(timeout: 3))
// Zoom and reset
video.pinch(withScale: 2, velocity: 1)
let reset = app.buttons["Reset zoom"]
XCTAssertTrue(reset.waitForExistence(timeout: 3))
snap("04c-player-zoomed")
reset.tap()
XCTAssertTrue(app.buttons["AirPlay"].waitForExistence(timeout: 3))
// Frame stepping
video.tap()   // pause
let mid = video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: 60, dy: 0)))
XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Frame'")).firstMatch.waitForExistence(timeout: 2))
snap("04d-player-frame-step")
```

Run the full suite: core tests, Smoke, Walkthrough (all 4). Expected all pass, zero warnings, no "notification not received" stalls.
