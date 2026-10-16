# Repaso Sub-project E (Several folders + Search) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let a video or clip appear in several folders (one home + links) and search the whole library.
**Spec:** `docs/superpowers/specs/2026-10-16-repaso-collections-search-design.md`

## Global Constraints
- Same as D: iOS 26 target, Swift 6 strict concurrency, zero warnings, mutations through `LibraryService`, no zero-duration keyframes, no non-finite layout values, no commits unless asked.
- The schema change must be additive with defaults (lightweight migration). Check on a phone with a real library before shipping.

## Review Focus
1. Linking an item to its own home folder must not show it twice there → `setLinks` filters the home (test).
2. Moving an item into a folder it was linked to must drop the link → normalisation test.
3. Deleting a folder that only *links* a video must not delete the video → delete-contents test.
4. Search with accents/case ("bachata" vs "Bachatá") must match → search test.
5. Opening an existing (pre-E) library must not crash or lose data → device check.

- [ ] **Task 1 — Core links:** `Original.linkedFolders`, `Clip.linkedFolders`, `Folder.linkedOriginals/linkedClips`; `LibraryService.setLinks`/`unlink` (both kinds), normalisation in `moveOriginal`/`moveClip`, delete-folder rules; `FolderContents` (originals/loose/counts/mosaic/queue include links; `isLinked(_:in:)`). Tests in `LinkTests.swift`.
- [ ] **Task 2 — Core search:** `LibrarySearch` with `Results { clips, videos, folders }`. Tests in `SearchTests.swift`.
- [ ] **Task 3 — Add-to-folders sheet + menus + badges** (`LinkSheet`, `LibrarySheet.link`, ClipRow/OriginalCard menus, `LinkBadge`).
- [ ] **Task 4 — Search screen** (`Route.search`, Home search pill, `SearchView`).
- [ ] **Task 5 — Walkthrough** (add to folders, badge, remove; search by name and by instructor), full suite, install over a real library on the phone.
