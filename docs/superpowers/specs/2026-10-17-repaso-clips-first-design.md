# Repaso — Sub-project H: Clips first, full videos on demand, keep-only-clips, Arrange mode — Design

Date: 2026-10-17
Source: the owner's fourth batch of feedback. Decisions marked *(Claude's call)* were made without a question round.

## 1. What the owner asked for

1. Once clips are cut from a video, the video shouldn't be the main thing holding its clips. Folders should show the **clips** (as preview cards). The full video is archived: there on demand (watch it, cut more), maybe on a separate page of full uploads.
2. Clips should still be trimmable in the cutter, but as an on-demand action, not up front.
3. An option to delete the full video once its clips are made, or keep it, to keep the library clean.
4. Dragging to a folder and the long-press menu both start with a long press and clash. Tell them apart.

## 2. Design

### 2.1 What a folder shows *(Claude's call)*
- **Folders**: subfolders, as today.
- **To cut**: videos in this folder that have **no clips yet** (card with poster, title, Cut). A video leaves this list once it has clips.
- **Clips**: every clip that lives here, as a **2-column grid of preview cards** (tall poster with live preview, name on a soft gradient, duration, ★ / ✓ marks). Tap plays; the Player's queue is the grid in order.
- A clip lives in the folder it's filed in, or its video's folder if not filed; clips linked here show too (with the 🔗 badge). So a clip filed in Hammerlock shows in Hammerlock only, no longer also under its video in Turns.
- **Unsorted** works the same way: videos with no folder and no clips yet ("To cut"), and their unfiled clips.
- Counts, mosaics and the Player queue follow the same rule.

### 2.2 Full videos on demand
- A **Videos** tile on Home (next to Unsorted and Favorites) opens **Full videos**: every imported video, newest first, each with poster, title, clip count, where it lives, and **Cut**. Long-press: Play, Edit details, Move, Add to folders, Delete.
- From any clip (long-press menu and the Player's "…"): **Play full video** and **Trim…**.

### 2.3 Trim on demand
- **Trim…** opens the cutter on the clip's video with that clip selected and the strip at it, so its handles are ready to drag.

### 2.4 Keep only the clips *(Claude's call: offer after cutting, and when deleting)*
- When you tap **Done** in the cutter after making clips, it asks: **Keep the full video?**, with **Keep full video** or **Keep only the clips**.
- Deleting a video that has clips offers both **Keep its N clips, delete the full video** and **Delete video and N clips**.
- Keeping only the clips saves each clip as its own short video (exact frames, re-encoded at high quality), then deletes the full video's file. Clips keep their names, notes, tags, favorites, links and folder. A progress line shows while it works.
- Afterwards a clip can still be trimmed, but only inside its own length, since the rest of the video is gone. Such clips have no "Play full video".

### 2.5 Drag versus menu: Arrange mode *(Claude's call)*
- **Press and hold** always opens the menu.
- To drag, turn on **Arrange**: a chip on folder screens, and on Home via **Arrange folders** in a folder's menu. While arranging, cards jiggle, menus are off, and press-and-hold-then-move drags: clips onto folders (spring-loading as before), folders to reorder on Home. **Done** ends it.
- Clip menus also offer **Move to folder…** for doing it without dragging.

## 3. Testing
- Core: folder clip lists (home, filed elsewhere, linked, Unsorted), videos-to-cut, counts and mosaics, detaching a clip into its own file keeps folder, links and favorites, deleting the full video afterwards.
- UI: walkthrough updated for clip cards and Arrange; Full videos page; Trim opens the cutter with the clip selected; keep-only-clips from the delete sheet.
- Device: clip export speed and quality on a real library.
