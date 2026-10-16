# Repaso Sub-project D (First on-device feedback) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Hold-to-seek, whole-video playback, easy rename, a sliding control panel, clip decks with bigger previews, and an import destination toast.

**Spec:** `docs/superpowers/specs/2026-10-16-repaso-practice-feedback-design.md`

## Global Constraints
- iOS 26.0 target, Swift 6 strict concurrency, zero warnings; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; destination `iPhone 18 Pro`.
- Tap on the video stays instant (no double-tap, long press never delays a tap).
- **No zero-duration keyframes** (`LinearKeyframe(x, duration: 0)`): use `MoveKeyframe`. Never pass non-finite values to layout. (Lesson from the device crash fixed on 2026-10-16.)
- Mutations through `LibraryService`. No commits unless asked.

## Review Focus
1. Holding to rewind at the very start of a clip must stop at the start, not seek before it → `HoldSeek.rewindStep` test.
2. A long press must not also count as a tap (no play/pause toggle on release) → manual + UI test.
3. Renaming to an empty name keeps the old one → existing `updateInfo` behaviour, UI check.
4. A deck for an original with 0 clips must not show → OriginalCard guard.
5. The slid-away panel must come back when paused, so controls are never lost → PlayerView `onChange(isPlaying)`.

---

### Task 1: Core `HoldSeek`
Files: `Packages/RepasoCore/Sources/RepasoCore/Playback/HoldSeek.swift`, tests in `PlayerExtrasTests.swift`.

```swift
public enum HoldSeek {
    public enum Zone: Equatable, Sendable { case rewind, none, forward }
    public static let minimumHold = 0.35
    public static let forwardRate = 2.0
    public static let rewindInterval = 0.25
    public static let rewindStep = 0.5
    public static func zone(forX x: Double, width: Double) -> Zone
    public static func rewindTarget(from t: Double, in range: ClosedRange<Double>) -> Double   // max(lower, t − 0.5)
}
```

### Task 2: `PlaybackItem` + whole-video playback
Files: create `Repaso/Player/PlaybackItem.swift`; modify `PlayerModel` (`load(_ item:)`), `PlayerView` (items instead of clips), `FolderSupport` (`PlayerRequest.items`), `FolderView`/`FavoritesView` (build items), `OriginalCard` (`onPlay` on poster tap).

### Task 3: Hold-to-seek in the Player
Files: create `Repaso/Player/HoldSeekGesture.swift` (UIKit long press bridge) and badge; modify `PlayerModel` (`beginHold(_:)`, `endHold()`), `PlayerView`.

### Task 4: Sliding panel
Modify `PlayerView`: `panelHidden` state, grabber, drag gesture, idle timer slides it away, pause/clip change restores.

### Task 5: Rename
Modify `PlayerView` panel name → inline `TextField`; `ClipTray` tap name renames any card; `ClipRow` context menu "Rename" first; `ClipInfoSheet` focuses the name when opened for rename.

### Task 6: Clip decks + bigger previews
Create `Repaso/Components/ClipDeck.swift`; modify `OriginalCard` (collapsed deck by default, matched geometry), `ClipRow` (64×44 poster, 64pt row).

### Task 7: Import toast
Modify `ImportCoordinator` (destination name, completion callback), `ImportSheet` title, `HomeView`/`FolderView` (toast with Open).

### Task 8: Tests and device
Update the walkthrough (expand deck, rename from Player, hold-seek badge, whole-video play, panel handle). Run core + all UI tests; build and install on the iPhone.
