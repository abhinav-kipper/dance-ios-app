# Repaso — Sub-project D: First on-device feedback — Design

Date: 2026-10-16
Source: the owner's first session with the app on an iPhone 15 (iOS 26.6). Builds on A–C.

Decisions marked *(Claude's call)* were made without a question round, as with B and C, and can change after the owner tries them.

## 1. What the owner asked for

1. Long-press the left or right side of a playing clip to rewind / fast-forward; the centre pauses.
2. Clip names ("Clip 1", "Clip 2"…) should be easy to rename.
3. The control panel should not only dim when idle but slide down so the whole video is visible, and be draggable back up with a finger.
4. Under each video in a folder, clips should look like a deck of preview cards that expands with motion.
5. (earlier) After importing from Home, nothing said where the video went.
6. (earlier) A way to watch and practise a whole video without cutting it.
7. (earlier) Previews could be a bit bigger.

## 2. Design

### 2.1 Hold to step frames (revised after first try)
- First version played at 2× / rewound at 2×. The owner asked for **frame by frame** instead, "so I can easily see the move".
- Holding the **right third** (≥ 0.35s) pauses and steps **forward one frame every 0.1s** (about ⅓ speed for 30fps video); the **left third** steps backward. Stepping stops at the clip's ends.
- The `Frame 0412` chip shows while holding, with a light haptic tick per frame. On release it **stays paused** on that frame; a tap resumes.
- The centre third has no long-press action; a tap anywhere still toggles play/pause instantly. The release of a hold is not treated as a tap.
- UIKit `UILongPressGestureRecognizer` via `UIGestureRecognizerRepresentable` (`cancelsTouchesInView = false`). Core: `HoldSeek.zone(forX:width:)`, `HoldSeek.frameStep(for:)`.

### 2.2 Whole-video playback
- `PlaybackItem` (app): `.clip(Clip)` or `.original(Original)`. The Player and `PlayerModel` take items; an original plays `0…duration`.
- For an original: favorite/learned buttons are hidden, zoom is not saved, share is hidden, the name isn't editable; everything else (speed, loop, gap, swipe, frame-step, zoom, hold-seek, AirPlay) works.
- Entry: tapping an original's thumbnail (in its card header) plays that video; the queue is that folder's originals, so swiping moves between videos.

### 2.3 Rename
- Rename fields open **empty with the current name as the hint**: typing replaces the name; return with nothing keeps it (prefilled text made typing append, e.g. "Clip 4Basic step").
- Player panel: tapping the clip name starts renaming in place. Playback keeps running.
- Cut: the `Clip 4 added` toast has a **Name** button that opens the new card's name for typing; card names show a small ✎ and tapping any name renames it. (No automatic keyboard after every cut, so cutting many clips stays fast.)
- Clip context menu: **Rename** is first and opens the Clip info sheet with the name focused.

### 2.4 Sliding control panel *(Claude's call: peek height and gesture)*
- When idle while playing (existing 2.4s timer), the top bar fades as now and the bottom panel **slides down** leaving a 30pt peek with a grabber (and dims to 42% as before).
- Drag the grabber/peek up (≥ 30pt or a flick) or tap it → panel slides back up. Dragging the open panel down by its grabber hides it.
- Pausing, swiping to another clip, or opening a sheet brings it back. Tapping the video only toggles play/pause (it no longer reveals the panel), so you can keep the video clear while practising.
- Reduce Motion: fade instead of slide.

### 2.5 Clip decks *(Claude's call: collapsed by default)*
- An original's clips are **collapsed into a deck** by default: up to 3 poster cards (96×64) stacked with 6pt offsets and −3°/0°/+3° rotation, plus `N clips` and a hint.
- Tapping the deck expands: the cards fly into the rows (matched geometry from deck card → row poster), rows rise in staggered (existing 45ms stagger). The chevron collapses them back into the deck. Expanded state is remembered per original for the session.
- Under Reduce Motion: fade between deck and list.
- Bigger previews: clip row posters 46×32 → **64×44** (row height 60 → 64), original header posters 64×44 → **88×60**.

### 2.6 Import destination
- When an import batch finishes, a toast says `1 video added to Unsorted` / `3 videos added to Turns` with an **Open** action that navigates there (from Home). The import sheet's title also names the destination: `Importing 2 videos to Unsorted`.

## 3. Testing
- Core: `HoldSeek` zones (edges, exact thirds) and rewind clamping.
- UI walkthrough: expand the deck before using clip rows; long-press right side shows the `2× »` badge; rename a clip from the Player panel; play a whole video from its thumbnail; the panel slides away when idle and comes back by dragging the handle.
- Device: hold-seek feel, panel drag, deck animation.

## 4. Out of scope
Per-clip speed, reverse playback with audio, haptic tuning beyond light taps.
