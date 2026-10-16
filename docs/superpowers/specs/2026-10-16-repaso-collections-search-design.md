# Repaso — Sub-project E: Videos and clips in several folders, and search — Design

Date: 2026-10-16
Source: the owner wants "the same video can exist in multiple folders … a move by a teacher can be a move category itself and video can be in both", and to find things later by searching. Design approved in chat: one home folder plus "Also add to…" folders with a link badge, then search.

## 1. Model

- Every video (`Original`) and clip keeps exactly **one home** (unchanged): `Original.folder` (nil = Unsorted) and `Clip.folder` (nil = with its video). Drag and drop and the Move sheet change the home.
- New many-to-many **links**: `Original.linkedFolders: [Folder]` ↔ `Folder.linkedOriginals`, and `Clip.linkedFolders: [Folder]` ↔ `Folder.linkedClips` (delete rule nullify on both sides). A link means "also show it here".
- Added with defaults, so SwiftData migrates existing libraries automatically (lightweight); no data is touched. Verified on the owner's phone (which has a real library) before shipping.

## 2. Rules (`LibraryService`)

- `setLinks(_ original: Original, to folders: [Folder])` / `setLinks(_ clip: Clip, to folders: [Folder])`: replaces the item's links. The item's **home is never also a link** (filtered out); duplicates collapse.
- `unlink(_:from:)` for both kinds: removes one link ("Remove from <folder>").
- **Normalisation:** whenever an item's home changes (move, drop, original moved and the clip lives with it), a link to the new home is removed.
- **Delete folder, delete contents:** items whose *home* is inside are deleted as before; items only *linked* there just lose the link. **Move contents up:** links on the deleted folder move to its parent (unless the parent is the item's home, or root).
- Deleting a video or clip removes its links (nullify).

## 3. What shows where (`FolderContents`)

- Folder screen: **Originals** = home originals, then linked originals (each linked card wears a 🔗 "Linked" badge and lists all its clips). **Loose clips** = home loose clips + linked clips (linked ones wear a 🔗 badge, meta `from <video>`).
- Counts and mosaics include linked items (each clip counted once).
- The Player queue for a folder includes linked items in the order shown.
- Unsorted and Favorites are unchanged (links don't apply to them).

## 4. UI

- **"Add to folders…"** in the long-press menu of clips and videos opens a multi-select folder tree (22pt indent, checkboxes). The home folder row is shown checked and disabled with "Home". Save → `setLinks`; toast `Added to 2 folders`.
- When an item is shown *via a link*, its menu also has **"Remove from <folder>"** (unlink, with Undo).
- 🔗 badge: small green-tint capsule with `link` symbol and "Linked" (accessibility "Linked here; home is <folder>").

## 5. Search

- A glass **Search** pill under the Home title opens a full-screen search screen with a focused field.
- `LibrarySearch.results(for:in:)` (core, pure, tested): case- and diacritic-insensitive; the query is split into words and **every word must match** one of the item's fields (prefix of a word in a field, or substring for 3+ characters).
  - Clips: name, note, video title, instructors, event, home folder and linked folder names.
  - Videos: title, instructors, event, home and linked folder names.
  - Folders: name and parent names.
- Results in three sections (Clips, Videos, Folders), at most 50 each, ranked: name match before other-field match, then most recently added. Tap a clip → plays it (queue = clip results); a video → plays the whole video; a folder → opens it.
- Empty query shows nothing ("Search clips, videos, teachers, events and folders").

## 6. Testing
- Core: links (home filtered, duplicates, normalisation on move/drop, delete-contents keeps linked items, move-up relinks), contents/counts with links, search (multi-word, diacritics, fields, ranking, limits).
- UI walkthrough: add a clip to another folder via "Add to folders…", see it there with the badge, remove it; search for a clip by name and by instructor.
- Device: install over the existing library on the owner's phone and check it opens with everything intact.
