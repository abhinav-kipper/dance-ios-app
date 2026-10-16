# Repaso — Sub-project B: Drag and drop, share, Photos clean-up, tags — Design

Date: 2026-10-16
Source brief: `~/Documents/UK_VISA_DOCS/repaso-handoff/HANDOFF.md` §5–§6 (+ `design/Main.dc.html`, `Folder.dc.html`, `Sheets.dc.html`)
Builds on: `2026-10-15-repaso-core-loop-design.md` (sub-project A, complete)

## 1. Intent

A made the core loop work with menus and sheets. B makes filing fast and direct, and finishes the import and share flows:

1. **Drag and drop.** Hold a folder card on Home to reorder it; hold a clip in a folder and drop it on a subfolder card to file it there.
2. **Share export.** Export only the clip's time range and hand the file to the system share sheet.
3. **Delete from Photos.** After an import, offer to remove the imported videos from Photos, so the camera roll stops filling up.
4. **Tags.** Instructor(s) and event fields on the import sheet, with suggestions from earlier imports.

**Success criteria (B)**

1. Reordering a Home folder card by drag persists after relaunch; other cards jiggle while dragging; the dragged card's slot shows a dashed placeholder; the order updates live.
2. Dropping a clip on a subfolder card files it there, plays the absorb animation, shows `Moved to <Folder>` with **Undo** for 3.8s, and Undo restores the previous location exactly.
3. Hovering a subfolder card for 0.9s fills its ring and opens that folder (spring-loading); the drag continues, and dropping anywhere on the opened folder files the clip there.
4. Share produces a file whose duration matches the clip (±0.1s) and opens the system share sheet.
5. "Delete N videos from Photos?" only removes assets whose import succeeded; Keep leaves Photos untouched.
6. Instructor/event values typed on the import sheet are saved on every original in that batch, and appear as suggestions on the next import.
7. All core tests and the UI walkthrough (extended with a drag-move and Undo) pass on the iPhone 18 Pro simulator, with zero build warnings.
8. Every drag has a non-drag alternative (Move sheet, Move up/down menu items) for VoiceOver and Reduce Motion users.

## 2. Key decision: system drag and drop, not a custom gesture

| | System DnD (`draggable` / `dropDestination`) | Custom long-press + `DragGesture` overlay |
|---|---|---|
| Co-exists with the A context menus | Yes, UIKit coordinates menu ↔ drag natively | No: both want the long press |
| Scrolling and auto-scroll | Native | Must disable scroll and hand-roll auto-scroll |
| Spring-loading into another screen | Drag session survives navigation | Gesture dies with the view |
| VoiceOver drag support | Built in | None |
| Exact lift visuals (scale + rotate) | Via a custom preview view | Full control |
| Knowing when a drag ends | Drop handler; cancel needs iOS 27 `onDragSessionUpdated` | Full control |

**Choice: system DnD.** It keeps the A context menus, scrolls correctly, and is the only way spring-loading can open a folder mid-drag. Its one gap is that iOS 26 has no "drag cancelled" callback (`onDragSessionUpdated` is iOS 27+). §4.4 covers that with a fallback.

## 3. Core changes (`RepasoCore`)

Every rule or number stays in the package and is tested with Swift Testing on an in-memory container.

### 3.1 LibraryService additions

```swift
/// Persists a full sibling order (used at the end of a Home reorder drag).
public func setFolderOrder(_ ordered: [Folder]) throws        // sortIndex = position; all must share a parent, else LibraryError.invalidMoveTarget

/// Files a clip into `folder` by drag. Returns nil when the clip already lives there (no-op, no save).
public func dropClip(_ clip: Clip, on folder: Folder) throws -> ClipMoveReceipt?

/// Undo for a drop: puts the clip back where the receipt says it was.
public func undo(_ receipt: ClipMoveReceipt) throws

/// Tags for a batch of originals. Instructors are trimmed, empty ones dropped, de-duplicated case-insensitively
/// (first spelling wins). An empty event becomes nil.
public func setTags(_ originals: [Original], instructors: [String], event: String?) throws

// addOriginal gains `instructors: [String] = []` and `event: String? = nil`, normalised the same way.
```

```swift
public struct ClipMoveReceipt {
    public let clip: Clip
    public let previousFolder: Folder?   // nil = "with its video"
    public let destination: Folder
}
```

- `Clip.effectiveFolder` (new, computed): `folder ?? original?.folder`. `dropClip` is a no-op when `effectiveFolder?.id == folder.id`.
- `dropClip` delegates to `moveClip`, so A's normalisation rule still holds (dropping a clip on its original's folder sets `folder = nil`).
- `undo` moves the clip to `previousFolder`; when that folder has since been deleted, the clip goes back with its video (`nil`).

### 3.2 Pure helpers

- `FolderOrder.moving(_ id: UUID, onto target: UUID, in ids: [UUID]) -> [UUID]` — live reorder: removes `id` and inserts it at `target`'s index (so dragging forward lands after the target, backward before it, like the iOS Home Screen). Unknown ids return the input unchanged.
- `TagText.instructors(from text: String) -> [String]` — splits on commas, trims, drops empties, de-duplicates case-insensitively.
- `TagText.lastToken(of text: String) -> String` and `TagText.completing(_ text: String, with suggestion: String) -> String` — the instructors field autocompletes the token after the last comma; completing replaces that token and appends `, ` so the next name can be typed.
- `TagSuggestions.instructors(for query: String, excluding: [String], in originals: [Original], limit: Int = 3) -> [String]` and `TagSuggestions.events(for:excluding:in:limit:)`:
  - Candidates are all distinct values (case-insensitive) across originals, ranked by use count, then by the most recent `importedAt`, then alphabetically.
  - Empty query → top `limit` candidates. Otherwise case-insensitive match: prefix matches (of the value or any word in it) first, then other substring matches.
  - Values equal (case-insensitive) to the query or in `excluding` are left out.
- `ClipExport.fileName(for clipName: String) -> String` — `<name>.mp4`, with `/ \ : ? * " < > |` replaced by `-`, trimmed, at most 60 characters before the extension, `Clip.mp4` when empty.
- `ClipExport.timeRange(start:end:duration:) -> ClosedRange<Double>` — clamped to `[0, duration]`, minimum 0.1s.
- `PhotosCleanupText.prompt(count:)` → `Delete 3 videos from Photos?` / `Delete this video from Photos?`; `.detail` → `They'll also leave iCloud Photos, so Repaso will have the only copy.`; results `Removed from Photos`, `Kept in Photos`, `Couldn't remove from Photos`, `Allow full Photos access in Settings to delete`.
- `ImportSummary.recordedLine(_ dates: [Date], calendar:) -> String?` — nil when empty; one day → `Recorded Oct 12, 2026`; a span → `Recorded Oct 9 – 12, 2026` (formatted with `Date.IntervalFormatStyle`, so cross-month and cross-year spans read correctly).

### 3.3 ClipExporter (core, AVFoundation)

```swift
public enum ClipExporter {
    /// Exports `range` of the video at `source` to `destination` (.mp4), reporting 0…1 progress.
    public static func export(source: URL, range: ClosedRange<Double>, to destination: URL,
                              progress: @escaping @Sendable (Double) -> Void) async throws
}
```

- `AVAssetExportSession` with `AVAssetExportPresetHighestQuality` (frame-accurate trim; passthrough would cut at keyframes and start early), `timeRange` from the clamped range, `export(to:as: .mp4)` (iOS 18+ async API), progress from `states(updateInterval: 0.1)`.
- Cancellation: cancelling the calling task cancels the export; a partial file is removed.
- Tested against `TestVideo`: exporting 1.0–2.0s of a 3s video yields a file of 1.0s (±0.15s).

## 4. Drag and drop (app)

### 4.1 Payload

`DragRef: Codable, Transferable { enum Kind { case folder, clip }; let kind; let id: UUID }` with `CodableRepresentation(contentType: .repasoDragRef)`. `UTType(exportedAs: "com.amudgal.repaso.drag-ref", conformingTo: .data)` is declared in `project.yml` (`UTExportedTypeDeclarations`). Using our own type means other apps ignore the drag and our targets ignore foreign drags.

### 4.2 DragState (app, `@Observable`, in `AppEnvironment`)

```swift
@Observable @MainActor final class DragState {
    private(set) var active: DragRef?   // what is being dragged, nil when idle
    private(set) var origin: UUID?      // folder screen the drag started on (nil = Home/Unsorted)
    func lift(_ ref: DragRef, from origin: UUID?)   // payload closure: the item lifted
    func activate()                     // the session really moved: drag mode on
    func end()                          // drop handled, drag cancelled, or fallback fired
}
```

The system evaluates the payload when an item lifts, and an item also lifts when the user only opens its context menu. So `lift` only records a **pending** drag; drag mode starts at the first real movement signal (an iOS 27 `.initial`/`.active` session phase, or the first hover over any target or screen catcher). A pending lift that never moves expires after 2.5s. Screens read `env.drag.active` to switch into drag mode (jiggle, "Drop to place", "Drop on a folder", pulsing targets).

### 4.3 Home: reorder folder cards

- Each folder card: `.draggable(DragRef(.folder, id)) { LiftPreview(folder) }` and `.dropDestination(for: DragRef.self, action:, isTargeted:)`.
- Lift preview (no environment-dependent subviews, it renders outside the hierarchy): a card-sized glass tile with the folder name and count, `scale 1.07`, `rotation −3°`, deep shadow (`black 50%`, radius 24, y 14), 1pt `white 30%` outline. The system adds the lift haptic.
- While `drag.active` is a folder:
  - The grid renders from a local `order: [UUID]` (seeded from the query at lift).
  - The dragged card's cell shows a **dashed placeholder** (24pt radius, 1.5pt `white 25%` dash `[6,5]`) at its current slot.
  - Other cards **jiggle**: `rotationEffect` ±0.8°, `.easeInOut(duration: 0.16).repeatForever(autoreverses: true)` (0.32s per cycle), each card starting with a random phase offset so they don't move in sync. Off under Reduce Motion.
  - When a card becomes targeted, `order = FolderOrder.moving(dragged, onto: target, in: order)` with `Theme.spring`. Live.
  - Subtitle reads **Drop to place** in green.
- On drop (any card, or the grid's container drop destination) or cancel: `setFolderOrder(order)` once, the placed card plays the **settle** keyframes (1.08 → 0.96 → 1, 0.65s), `drag.end()`.
- Accessibility alternative: the existing context-menu **Move up / Move down** stay.

### 4.4 Knowing when a drag ends

- **Drop:** the drop handler calls `drag.end()`.
- **iOS 27+:** the dragged view also has `.onDragSessionUpdated { if case .ended = $0.phase { drag.end() } }` (behind `if #available(iOS 27, *)` in a `DragSource` modifier).
- **iOS 26 fallback:** each screen in drag mode installs a full-screen `dropDestination` "catcher" behind its content. Every target and the catcher report `isTargeted` changes to `DragState`, which counts how many are targeted. When that count drops to zero and stays zero for 0.3s, the drag has ended (cancelled over the screen or released outside every target). The 0.3s grace absorbs the exit-then-enter order when the finger moves from the catcher onto a card.
- Ending twice is harmless (`end()` is idempotent; the Home commit uses the order captured at the time).

### 4.5 Folder: drop a clip on a subfolder

- Clip rows (under originals and loose): `.draggable(DragRef(.clip, id)) { ClipLiftPreview(clip) }` — a 60pt glass pill with name and duration, `scale 1.04`, `rotation −2.5°`, deep shadow, 1pt outline. The source row dims to `opacity 0.28, scale 0.97` while it is being dragged.
- While `drag.active` is a clip:
  - The subfolder section label reads **Drop on a folder** in green.
  - Every subfolder card's border **pulses** between `accent 25%` and `accent 60%` (1.2s cycle).
- **Hover** (card `isTargeted`): card scales **1.08**, lifts **4pt** (`offset y −4`), 1.5pt green border, `accentTint` fill, and a 2.5pt green **ring** around a small folder badge fills over **0.9s** (linear).
- **Spring-loading:** when the ring completes while still targeted, a light haptic plays and the folder opens (`path.append(.folder(id))`). The drag continues.
- **Drop on a card:** `dropClip(_:on:)`. If it returns a receipt: the card plays **absorb** keyframes (scale 1.1 → 0.92 → 1.04 → 1 over 0.6s, `keyframeAnimator`), a loose clip leaves the list (existing slide-right + fade + collapse transition, 0.45s), a clip under an original gains its `In <Folder>` tag, a success haptic plays, and the toast `Moved to <Folder>` shows **Undo** for 3.8s (`env.showToast`). Undo calls `undo(receipt)`. No receipt (already there) → nothing happens.
- **Drop on a folder screen:** every `FolderView` for a real folder has the full-screen catcher from §4.4 also act as a drop target: dropping a clip anywhere on the screen files it into *this* folder (same receipt, toast and Undo; no absorb). When the drag started on another screen (`drag.origin` differs, i.e. it arrived by spring-loading), a green banner `Drop to file in <Folder>` shows at the top and the catcher accepts the drop. On the drag's own screen the catcher ignores drops, so releasing over blank space cancels instead of re-filing the clip. This is what makes spring-loading useful.
- Unsorted and Favorites screens have no drop targets (no subfolders, and dropping "into Unsorted" isn't a clip location).

## 5. Share export (app)

- Entry points: clip context menu **Share** (new `ClipActions.share`) and the Player panel **Share** button (`square.and.arrow.up`, after Learned, 44×44, label "Share clip"). The Player pauses while the share sheet is up.
- `ShareSheet(clip:)` (Sheet material, medium detent): clip poster 120×80 with duration badge, clip name, `Exporting 82%` (mono, numeric transition) over a 4pt progress bar (green fill). On success it presents `UIActivityViewController` (via `UIViewControllerRepresentable`) with the file URL; when that completes or is dismissed, the share sheet dismisses itself.
- Output: `tmp/Exports/<ClipExport.fileName>`; the folder is emptied before each export and at launch.
- Errors: missing source file → `Video file missing`; export failure → `Couldn't export this clip` with **Try again**. Dismissing during export cancels it.

## 6. Import sheet additions (app)

### 6.1 Tags

- Under the rows: **Instructor(s)** (`Who taught it`) and **Class or event** (`Where it was`) text fields in Control glass (44pt min height).
- Under each focused field: up to 3 suggestion chips (`accentTint` pill, green text, 36pt tall in a 44pt hit area) from `TagSuggestions`. Tapping an instructor chip completes the last token (`TagText.completing`); tapping an event chip replaces the field.
- `ImportCoordinator` owns `instructorsText` and `eventText` for the current batch (reset when a new batch starts). New originals are inserted with the current tags. Edits apply to every already-imported original in the batch via `setTags` on submit, on focus loss, and when the sheet disappears.
- A `Recorded Oct 12, 2026` line (from `ImportSummary.recordedLine` over the batch's `recordedAt` dates) sits above the fields, hidden when no date is known.
- Display: the Original card meta becomes `<event> · N clips` when an event is set; the Player source line becomes `<instructors joined by " & "> · <event>` when tags exist, falling back to A's `<title> · <recorded date>`.

### 6.2 Delete from Photos

- The picker becomes `photosPicker(..., photoLibrary: .shared())` so each `PhotosPickerItem` carries its asset `itemIdentifier`; the coordinator stores it per item.
- When the batch is finished (no item waiting or copying) and at least one item is `done` with an identifier, a rose-tinted card shows `PhotosCleanupText.prompt(count:)`, the detail line, and **Keep** / **Delete** buttons (44pt pills; Delete is rose with black text).
- **Delete:** `PHPhotoLibrary.requestAuthorization(for: .readWrite)`. With `.authorized` or `.limited`, fetch `PHAsset.fetchAssets(withLocalIdentifiers:)` for the done items only and run `PHAssetChangeRequest.deleteAssets` in `performChanges` (iOS shows its own confirmation). Success → `Removed from Photos`. User cancels the system alert → `Kept in Photos`. Denied/restricted, or no assets fetchable under limited access → `Allow full Photos access in Settings to delete`. Other errors → `Couldn't remove from Photos`.
- **Keep:** `Kept in Photos`. The result replaces the card as a single centred caption. The decision belongs to the batch, so a new import asks again.
- Failed items are never deleted from Photos.

## 7. Motion summary (B)

| Moment | Value | Reduce Motion |
|---|---|---|
| Lift | system lift + preview scale 1.07 / −3° (folder), 1.04 / −2.5° (clip) | preview unrotated, unscaled |
| Jiggle | ±0.8°, 0.32s cycle, random phase | off |
| Live reorder | `Theme.spring` | `.easeOut(0.2)` |
| Hover target | scale 1.08, y −4, ring 0.9s linear | no scale/lift; ring kept |
| Absorb | 1.1 → 0.92 → 1.04 → 1, 0.6s | off |
| Settle (Home) | 1.08 → 0.96 → 1, 0.65s | off |
| Target pulse | border 25% ↔ 60%, 1.2s | static 40% |
| Toast | existing slide-up spring | existing |

## 8. Error handling

| Failure | Behaviour |
|---|---|
| Drop payload refers to a deleted clip/folder | Ignored, `drag.end()` |
| `setFolderOrder` / `dropClip` save fails | `Couldn't save` toast (A's `env.perform`), context rolled back |
| Undo after the clip was deleted | Ignored (receipt clip `isDeleted`) |
| Export fails or file missing | Message + Try again in the share sheet |
| Photos access denied | Result caption tells the user to allow full access; nothing deleted |
| Tag save fails | `Couldn't save` toast; fields keep their text |

## 9. Testing

**Core (Swift Testing):**
- `setFolderOrder` persists positions and rejects mixed parents.
- `dropClip`: from original's folder to subfolder; loose clip to another folder; drop on its own effective folder → nil and no change; drop on the original's folder resets `folder` to nil; `undo` restores nil and non-nil previous folders; undo after the previous folder is deleted puts the clip with its video.
- `FolderOrder.moving` forward, backward, onto itself, unknown ids.
- `TagText` split/dedupe/completion; `TagSuggestions` ranking, prefix-before-substring, exclusion, limit, empty query.
- `setTags` and `addOriginal` normalisation.
- `ClipExport.fileName` sanitising and `timeRange` clamping; `ClipExporter` real export duration; `PhotosCleanupText`; `ImportSummary.recordedLine` single day and span.

**UI (XCUITest, seeded):** extend `WalkthroughTests` after the Cut step: in Turns, `press(forDuration: 0.4, thenDragTo:withVelocity:thenHoldForDuration: 0.3)` the **Wrap and unwrap** row onto the **Hammerlock** card. Two traps found while building it: a long first hold (0.8s) opens the context menu, and moving up into the menu selects menu items instead of dragging; and the card must be queried as `Hammerlock,` because `Hammerlock exit` (a clip row) also starts with "Hammerlock"; assert the `Moved to Hammerlock` toast and a second `In Hammerlock` tag; screenshot; tap **Undo**; assert one `In Hammerlock` tag again; then continue with A's menu-driven move. Add a Home reorder drag (Footwork card onto Turns) asserting the new order by element frames, and a spring-load test (hold 1.6s over the card, release on the opened folder, assert the toast and the opened folder).

**Manual on device (not automatable in the simulator):** Photos deletion with real picked videos, the system share sheet targets, spring-loading feel, iOS 26 cancel fallback.

**Commands:**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Repaso.xcodeproj -scheme Repaso -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

## 10. Out of scope (B)

Dragging folders into other folders, reordering subfolders inside a folder, reordering clips, dragging originals, multi-item drags, editing tags after import, filtering by tag, Player swipe/frame-step/zoom/AirPlay and live previews (C).
