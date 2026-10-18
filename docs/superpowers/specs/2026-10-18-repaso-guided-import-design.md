# Repaso: Sub-project I, guided import and one kind of thing (clips) — Design

Date: 2026-10-18
Source: the owner's description of how importing should work. Anything marked *(Claude's call)* was decided without asking; the owner can overturn it.

## 1. Intent

Bringing a class video in should feel like a short, friendly guide rather than a set of screens to work out: pick → watch → cut the moves → name them → file them → done.
Underneath, the app stops having two kinds of thing ("full videos" and "clips"). There are only **clips**. A clip may cover a whole video. That one rule removes the Full videos page, the "To cut" list, "Play full video", hidden clip-source videos and the video-only sheets, and it keeps every surface simple.

The owner has said existing data on the phones doesn't matter (early stage), so the model is changed properly rather than worked around. Code quality and a clean model come first.

### Goals
- A step-by-step import for one video, and the same steps repeated cleanly for several.
- Every clip has a **name** (required) and optionally **instructors**, given when it's made.
- The full video is just one more clip if you keep it; if you don't, it's gone.
- **Continue later** at any point: unfinished videos wait in **Unsorted**, which now means "videos still to go through".
- The last step files **each clip** in a folder, with search and quick New folder.
- The same pink and green look, and the same lively motion the cutter has now (the pink flash on Mark, snaps and springs).

### Non-goals
- No new browsing, moves catalogue, tags system or Home redesign; the owner will direct those separately.
- No change to the Player, the notebook, frame stepping, Arrange mode or drag-to-folder beyond what the model change forces.
- No data migration. The store is reset (see 4.4).

### Anti-goals (a failure even if it works)
- A guide that feels like a form: long screens, many fields, small text, or steps that can't be skipped when they don't apply.
- Losing work: a named clip must never vanish because the user tapped Continue later, closed the app or the app was killed.
- Anything that looks like the old "video vs clip" split coming back (a video badge, a separate list of full videos, a "parent" wording).

## 2. The flow

### 2.1 Single video
1. **Pick.** The Photos picker as today (Videos with Screen recordings included). Picking one video starts the guide at once in a full-screen cover. The file copies in the background; the first step shows the video as soon as it can play, with a slim progress line until then.
2. **"Make clips from it?"** The video plays with sound, as in the cutter, with two big buttons at the bottom:
   - **Make clips** (green): goes to step 3.
   - **Use the whole video** (pink outline): skips to the name card for one clip covering the whole video, then to step 5.
3. **Cut.** Today's cutter (scrolling strip, pinch zoom, fixed playhead, overlay time/play, Mark start / Mark end, handles to trim, the hints). On **Mark end** the pink flash plays as now, then the **name card** slides up (2.4). Saving it drops the new clip into the strip with a small spring and the next Mark is ready. A **Done** button appears once there is at least one clip.
4. **"Keep the full video too?"** Shown only after Make clips. Poster of the whole video, and two buttons:
   - **Keep it**: the name card again, for a clip covering the whole video (prefilled with the video's date title, selected so typing replaces it).
   - **Delete it**: under the button, one quiet line: "Your clips stay. They can only be trimmed shorter later."
5. **File them.** A list of the clips from this video (each: small poster, name, a folder chip). Tapping a chip opens the folder picker (2.5). Each clip's chip starts as the folder chosen for the clip above it *(Claude's call: per-clip as asked, but one tap per clip when they all go to the same place)*; the first clip's chip starts as the folder last used in any import, or empty. **Finish** is enabled when every clip has a folder.
6. **Done.** The cover closes with a toast "3 clips saved · Go to" (Go to opens the first clip's folder). The existing "Delete from Photos?" offer follows, as today.

A small step indicator (pink dots, the current one a green pill, like the guide) sits at the top: Trim? · Cut · Keep? · File. Steps that don't apply are skipped, not shown greyed.

### 2.2 Several videos
- Picking several starts the same guide with a header **"Video 2 of 5"** next to the dots. All files copy in the background one after another (as the coordinator does now), in pick order.
- Finishing step 5 for one video slides straight to step 2 of the next (horizontal slide, the same spring as elsewhere).
- Instructor suggestions carry over (2.4), and so does the folder default, so a batch of one class is fast.
- After the last video: one toast for the batch ("12 clips from 5 videos · Go to") and one Photos offer for all of them.

### 2.3 Continue later
- A **Continue later** button sits top-left on every step (top-right stays for the step's own action).
- Tapping it closes the guide. The current video and every video not yet finished go to **Unsorted**. Clips already named for the current video are kept with it (they were saved when named, see 4.2), so nothing is lost.
- Closing the app or the app being killed mid-guide behaves the same: next launch, those videos are in Unsorted.
- **Unsorted** on Home is a tile ("Unsorted · 3") only while something is waiting. It opens a simple grid of the waiting videos (poster, date title, "2 clips so far" when some exist). Tapping one opens the guide for that video only: at step 3 with its clips in the strip if it already has clips, otherwise at step 2. Long-press: **Delete** (removes the video and any clips made from it so far, with a confirm).
- Videos waiting in Unsorted never appear anywhere else (not in search, folders, Favorites or the Player).

### 2.4 The name card
- A bottom card over the cutter. The video stays visible above it, paused on the clip's first frame *(Claude's call: paused, to keep it calm)*.
- **Name**, required, autofocused. Suggestions as you type from names already used (chips under the field, like the import tag chips today). Save is disabled until the name has a non-space character; the keyboard's return key saves.
- **Instructors**, optional, one line, comma-separated like today's import field, prefilled with the instructors of the last clip saved in this guide session, with suggestion chips from all instructors used.
- **Save clip** (green) and **Cancel** (drops the marked range, not the video).
- Event/class name is no longer asked for *(Claude's call: the owner listed only name and instructor)*.

### 2.5 The folder picker (step 5)
- A sheet with a **search field** at the top that filters the folder tree as you type (matches show with their path, "Turns › Hammerlock").
- **New folder** row at the top, as the current pickers have. If the search text matches no folder, the row reads **Create "Hammerlock"** and creates it in one tap. Creating offers "on Home" or "inside" the folder currently highlighted, as today's NewFolderRow does.
- Picking a folder closes the sheet and the chip updates with a short pink pulse.
- One folder per clip here. Adding a clip to more folders stays where it is today (Folders… in the Player and clip menus).

### 2.6 Motion and look
- Pink for finding and choosing (step dots, folder chips, Continue later, Unsorted), green for doing (Make clips, Save clip, Finish), as in the Theme rule now.
- Steps slide in from the right; the name card springs up; a saved clip flies down into the strip; the folder chip pulses pink when set; Finish shows a quick green check before the cover closes.
- Reduce Motion swaps slides and springs for fades, as `Theme.motion` already does.

## 3. Everywhere else, after the change
- **Folders** show clips (grid as now) and subfolders. The "To cut" section goes.
- **Home** loses the Videos tile and the Full videos page. Unsorted changes meaning (2.3).
- **Clip menus and the Player's "…"**: Name & note…, Trim…, Folders…, Share, ★, ✓, Delete. "Play full video" goes. Trim opens the cutter on the clip's recording with the clip selected, as now; its range is limited to the recording (the whole video if it's still there, the clip's own file if not).
- **Deleting a clip that covers a whole video while other clips use the same video**: asks "Delete the full video? Your N other clips stay. They can only be trimmed shorter later." and then works like "Delete it" in step 4.
- **Search** finds clips by name, instructors, note and folder. Video notes and events go away with the video type.
- **Guide (onboarding)** cards are rewritten for the new import (one card replaces "Bring in your class videos" and "Cut the moves you want").

## 4. Model

### 4.1 Types *(Claude's call on names and shape)*
- **`Recording`** (internal, never shown as a thing): `fileName`, `duration`, `recordedAt`, `importedAt`, `photosAssetID?`, `isPending: Bool` (true while in the guide or Unsorted), `sortIndex` (Unsorted order), `clips` (cascade). It replaces `Original`. It has no title, folder, note, instructors, event, links or clip-number counter.
- **`Clip`**: `name` (non-empty), `instructors: [String]`, `start`, `end`, `note`, `isFavorite`, `isLearned`, `lastPlayedAt`, `addedAt`, `sortIndex`, `zoom`/`panX`/`panY`, `recording`, `folder` (its home; nil only while its recording is pending), `linkedFolders`.
- "Covers the whole video" is derived: `start == 0 && end == recording.duration` (with a small tolerance); nothing stores it.
- `Folder` loses `originals` and `linkedOriginals` and gains `isOrphans: Bool = false`.

### 4.2 Rules (in `LibraryService`, tested in RepasoCore)
- Saving a name card creates the clip at once (folder nil, recording pending). Step 5 sets folders; **Finish** sets `isPending = false` in the same save.
- A recording's file is deleted only when no clip uses it any more.
- "Delete it" (step 4) and deleting a whole-video clip that has siblings: each other clip of that recording is exported to its own new recording (exact frames, HighestQuality, as `detach` does today; progress shown), then the old recording and its file go. Exported clips keep everything (name, instructors, note, ★, ✓, zoom, folder, links).
- Deleting a pending video from Unsorted deletes its clips and file.
- **When "Delete it" runs** *(Claude's call)*: the step 4 choice is stored on the recording (`keepWholeVideo: Bool?`, nil until answered) and carried out at **Finish**, before `isPending` is cleared. Continue later keeps the choice; if the guide resumes at step 3 and new clips are added, step 4 is asked again.
- **If the export fails or the app is killed during it** *(Claude's call)*: nothing is committed until every clip exported. New files made so far are deleted, the old recording and its clips are untouched, and the video stays pending (in Unsorted on next launch) so Finish can be retried. No "export in progress" state is persisted.
- **Finish is per video** *(Claude's call)*: each video leaves pending at its own step 5. If the app dies in video 3 of 5, videos 1 and 2 are filed and 3 to 5 are in Unsorted.
- **Photos offer** *(Claude's call)*: offered at the end of a guide session for every video finished in that session (a batch, or a single video resumed from Unsorted). `photosAssetID` is kept on pending recordings for this.
- **Whole-video prompt** applies only when the recording has other clips. A clip that was exported into its own file is that recording's only clip, so it never triggers the prompt and needs no flag.
- **Clips always live in a folder** once filed. There are no loose clips on Home and clips can't be dropped on Home. Deleting a folder works as today (move contents up a level, or delete contents), except that clips with nowhere to go (their folder was top-level) move **automatically to an "Orphans" folder** on Home *(owner's decision)*. Orphans is created the first time it's needed, is flagged on the model (`Folder.isOrphans`) so it's found again even if renamed, and is otherwise a normal folder. Deleting Orphans itself only offers "delete contents".
- Search, folder contents, Favorites, counts, mosaics and the Player queue ignore clips whose recording is pending.

### 4.3 What goes
`Original`, `isClipSource`, `FolderContents.videosToCut` / `unsortedVideosToCut` / `allVideos` / `showsThroughLink` for originals, `OriginalCard`, `VideosView`, `VideoInfoSheet`, `DeleteOriginalSheet`, the import sheet's tag fields and per-video ✎ details, `PlaybackItem.original`, "Play full video", the Home Videos tile. Tests that cover these are removed or rewritten.

### 4.4 Store reset *(owner approved, because it avoids real work)*
Moving from `Original` to `Recording` (and moving title, instructors and folder onto clips) is not a change SwiftData can migrate on its own: it would need the old schema kept as a versioned copy plus a one-off conversion stage and its tests, only ever run on two phones. So: a new store file name for the new schema; on launch the old store and the library's video files are deleted and the app starts empty. Videos still in Photos can be imported again.

## 5. What's left to the builder
- Exact copy of buttons and hint lines (keep the house voice: short, plain, no "successfully").
- Exact animation curves and timings, within the existing `Theme.motion` style.
- How `ImportCoordinator` and `CutModel` are reshaped to drive the guide (a guide model that owns the queue and the current step is suggested, not required).
- Whether the folder picker's search is built into the existing tree view or a new one.

## 6. Testing
- **Core (Swift Testing):** creating clips on a pending recording; Finish clears pending and requires every clip to have a folder; pending recordings and their clips are hidden from folder contents, search, Favorites and counts; whole-video detection; deleting the whole clip with siblings exports them and removes the old file only after; deleting a pending video removes its clips and file; file is kept while any clip uses it.
- **UI (XCUITest, seeded):** single video, Use the whole video → name → folder → saved; Make clips → two named clips → Delete it → files → saved and playable; several videos with Continue later after the first → the rest in Unsorted → resume one at the cut step with its clips; name is required (Save disabled when empty); Create "X" from the folder search.
- **Device:** a real batch import on both phones; export speed for Delete it on a long video.
