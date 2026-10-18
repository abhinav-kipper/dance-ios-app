# Repaso — Sub-project G: Picker albums, per-video import tags, tidy Unsorted, notes, how-to guide — Design

Date: 2026-10-17
Source: the owner's third batch of feedback. Decisions marked *(Claude's call)* were made without a question round.

## 1. What the owner asked for

1. The Screen Recordings album doesn't show in the video picker. Is the app seeing a restricted library?
2. Importing several videos gives one instructor field for all of them, but they can be different classes, names and teachers. Keep the flow simple.
3. A clip moved out of Unsorted into a folder still shows in Unsorted (only moving the whole video clears it).
4. Notes on videos can't be seen, written or edited.
5. There's no guide to what you can do (long-press, pause, …).

## 2. Design

### 2.1 Picker
- Not restricted: the system picker always shows the whole library and needs no permission (the "delete from Photos" permission is separate and doesn't affect it).
- The picker was filtered to plain `.videos`, which hides the Screen Recordings (and Slo-mo, Cinematic) collections. The filter becomes **videos, screen recordings, slo-mo and cinematic videos**.

### 2.2 Per-video tags at import *(Claude's call: "same for all" plus per-video override)*
- The two fields stay at the bottom as **"For all videos"** (Instructor(s), Class or event). That's the common case: one class, several takes.
- With 2+ videos, each video row gets a **pencil**. Tapping it opens that video's own fields inline: **Name**, **Instructor(s)**, **Class or event**. Empty fields show the shared value as their hint, so "empty" means "same as all".
- A row with its own values shows them under its name (e.g. "Ataca & Alemana · Berlin").
- Saving works as today (on leaving a field and when the sheet closes): each video gets its own values where set, otherwise the shared ones. A name typed here becomes the video's title.

### 2.3 Unsorted is an inbox
- In **Unsorted**, a video's list of clips leaves out clips already filed in a folder. When some are filed, the card says "2 filed in folders" so nothing seems lost.
- Folder screens are unchanged (clips filed elsewhere still show under their video with the "In Hammerlock" tag), as are counts.

### 2.4 Notes
- Videos get a **note** (same 140-character limit as clips). Existing libraries migrate automatically (new optional field).
- **Edit details…** for a video (long-press menu on its card, and the Player's "…" menu) opens a sheet with **Title, Note, Instructor(s), Class or event**.
- Clips: the long-press item "Rename" becomes **"Name & note…"**, and the Player's "…" menu gets the same item, so clip notes are easy to find. Tapping the name in the Player still renames in place.
- Notes show: a video's note under its title on its card (2 lines); in the Player panel for both clips and whole videos (as clip notes do today).

### 2.5 How-to guide *(Claude's call: swipeable cards, shown once, always reachable)*
- On first launch a full-screen guide of 6 swipeable cards (icon, title, 2–4 short lines each):
  1. **Import**: from Photos; tag the teacher and class; go straight to where it landed.
  2. **Cut clips**: Mark start / Mark end; scroll the strip, pinch to zoom; drag a clip's handles to trim.
  3. **Practise**: tap the middle to play/pause; tap a side for one frame, hold a side to step; swipe up/down for the next clip; pinch to zoom.
  4. **Controls**: the panel slides away while playing; drag its handle up; speed, loop and pause-before-repeat; star, learned and "…" for more.
  5. **Organise**: long-press anything for its menu; drag clips onto folders; Add to folders to show it in several; New folder from any folder picker.
  6. **Get around**: swipe right to go back; hold Back to jump Home; search teachers, events and names.
- **Skip** at the top, **Next** / **Start practising** at the bottom, page dots.
- Reopened any time from a **?** button next to New folder on Home.
- Not shown automatically during UI tests.

## 3. Testing
- Core: video note save/clear/limit; per-video tag resolution (own value vs shared); Unsorted clip filter.
- UI: per-video tag override in the import sheet can't be driven without Photos, so it's covered by core tests; UI tests cover the guide (open from ?, page through, close), Edit details on a video (note shows on the card), "Name & note…" on a clip, and a filed clip leaving Unsorted.
- Device: Screen Recordings album appears in the picker.
