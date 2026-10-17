# Repaso — Sub-project F: Native navigation gestures, scrollable Cut strip, bigger Cut video, quick folders — Design

Date: 2026-10-17
Source: the owner's second batch of on-device feedback. Decisions marked *(Claude's call)* were made without a question round and can change after the owner tries them.

## 1. What the owner asked for

1. Native iPhone gestures (swipe etc.) to go back in a folder, back to Home, or forward.
2. In Cut, the filmstrip only shows the next minute once the playhead gets there; for long videos you should be able to scroll left/right to reach the minute you want.
3. In Cut the video is too small; rework sizes and placement.
4. No quick way to create a folder from anywhere, e.g. while moving clips out of Unsorted.

## 2. Design

### 2.1 Navigation gestures
- **Swipe back** works again on every pushed screen (folder, Unsorted, Favorites, Search). The hidden navigation bar had switched off UIKit's edge swipe; the app re-enables the interactive pop gesture whenever there is something to pop. On iOS 26 the **swipe from anywhere** on the page (`interactiveContentPopGestureRecognizer`) is enabled as well, so a right swipe in the middle of the screen also goes back.
- **Back to Home** *(Claude's call)*: long-press the back button in a folder for a menu of every level above it (Home, then each parent), like Safari/Files back-button history. Picking one jumps straight there.
- **Forward**: iOS has no forward gesture in its navigation stacks, so there isn't one (adding a custom one would fight the system's back swipe).
- **Cut**: swipe down on the video closes Cut, like closing a photo (an unfinished mark is cancelled). The Player keeps swipe up/down for next/previous clip and closes with its ⌄ button.

### 2.2 Scrollable Cut strip *(Claude's call: fixed playhead, like Photos/iMovie)*
- The playhead is a fixed line in the **middle** of the strip; the filmstrip of the **whole video** scrolls underneath it with normal iOS scrolling (momentum included). Scrolling moves the video to the time under the playhead; while it plays, the strip glides along.
- Zoom: about 30s fits across the screen; **pinch** the strip to show more (up to the whole video, or 5 minutes) or less (down to 8s) so a long video can be crossed quickly.
- Tapping a spot on the strip scrolls it to the playhead.
- Clip ranges, the rose recording range and the trim handles live on the scrolling strip and move with it. Dragging a handle trims (the strip doesn't scroll during that drag).
- Frames: one thumbnail tile every few seconds along the whole video, loaded lazily as they come into view.
- Below the strip: the times at the left and right edges, and the hint "Scroll to move · pinch to zoom" (or "Drag the handles to trim" with a clip selected).
- VoiceOver: the strip is adjustable (±1s).

### 2.3 Bigger Cut video
- The video takes **all remaining height** instead of a fixed 430pt.
- The time readout, −5s / play / +5s go on **one compact row** (time on the left, 17pt mono); Mark start/end becomes 54pt tall; spacing tightened.
- Result on a 6.3" phone: the video gets roughly 100–130pt more height.

### 2.4 Quick folders
- The **Move** sheet and the **Add to folders** sheet get a **New folder** row at the top. It asks for a name. If a folder is selected (Move) it offers **Create in <that folder>** as well as **Create at top level**. The new folder is then selected (Move) or ticked (Add to folders), ready to confirm.
- Unsorted's move flow is the Move sheet, so this covers "moving from the inbox".

## 3. Testing
- Core: strip geometry (time ↔ content offset, zoom clamp, keeping the playhead's time when zooming).
- UI: swipe back from a folder; long-press back → Home; create a folder from the Move sheet and move a clip into it; scroll the Cut strip and see the time change; swipe down closes Cut.
- Device: feel of the strip scrolling and the swipe from anywhere.

## 4. Out of scope
Forward navigation; landscape Cut layout; per-frame thumbnails in the strip.
