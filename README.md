# Repaso

Repaso turns a camera roll full of bachata class videos into a sorted library of short clips you can watch, slow down and loop instantly. Import a class once, cut the moves you want to practise, file them in folders, and practise from the folder. Everything stays on the phone: no account, no sync, no server.

It's a native SwiftUI iPhone app (iOS 26+, Liquid Glass), dark-first, built to replace a slow web app.

## What it does

**Library**
- Import videos from Photos (multi-select, copied in the background with progress), tag them with instructor and class/event (suggestions from earlier imports), and optionally delete the originals from Photos afterwards.
- Folders with subfolders, plus pinned **Unsorted** and **Favorites**. Hold and drag folder cards on Home to reorder them.
- Each video lists its clips underneath, wherever those clips have been filed. Drag a clip onto a subfolder to file it there (hover to open the folder mid-drag), with Undo.
- Sort by manual, name, date added or recently played; hide learned clips.
- Thumbnails are cached poster frames, with muted live previews on up to 4 visible rows at a time.

**Cut mode**
- Mark start / Mark end to create a clip instantly, a Photos-style filmstrip with trim handles (0.5s minimum), and a tray of clips you can rename.

**Player**
- Tap to play/pause with zero delay (no double-tap anywhere).
- Speeds 0.5× / 0.75× / 1× with pitch-corrected audio, loop, and an optional 1–2s pause before each repeat.
- Swipe up/down for the next/previous clip in the folder; drag sideways while paused to step frames; pinch to zoom (1–3×), remembered per clip.
- Favorite, learned, share (exports just the clip's range), AirPlay. The screen stays awake while playing.

Accessibility: every control has a VoiceOver label and is at least 44×44pt, drag-and-drop has menu alternatives, and Reduce Motion removes overshoot, jiggle, slides and live previews.

## Requirements

- macOS with **Xcode 27** (builds for iOS 26+; tested on the iPhone 18 Pro simulator, iOS 27)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`); the Xcode project isn't checked in
- No third-party runtime dependencies

If `xcode-select` points at the Command Line Tools and you can't change it, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Getting started

```bash
xcodegen generate
open Repaso.xcodeproj
```

Run the **Repaso** scheme on an iPhone simulator or device. For a device, set your Team ID in `project.yml` (`DEVELOPMENT_TEAM`) first.

## Tests

Logic (library rules, sorting, cut maths, loop timing, gestures, zoom, preview budget, tag parsing, export) lives in the `RepasoCore` Swift package and is covered by Swift Testing tests. The app target has XCUITests.

```bash
# everything: package tests + UI tests
xcodebuild test -project Repaso.xcodeproj -scheme Repaso -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# package tests only (fast)
xcodebuild test -project Repaso.xcodeproj -scheme Repaso -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:RepasoCoreTests
```

The walkthrough UI tests drive a seeded library and need a sample video in the app's Documents folder; without it they're skipped:

```bash
cp sample.mov "$(xcrun simctl get_app_container booted com.amudgal.repaso data)/Documents/seed.mov"
```

UI tests: a smoke test, the seeded walkthrough (import-free core loop, drag-move with Undo, player swipe/zoom/frame-step), Home reorder and spring-loaded drop, an accessibility audit of Home, Folder, Cut and Player (fails on tap areas, labels and traits; contrast and Dynamic Type findings are attached to the results for review), and a 240-clip scroll test. The simulator only reports scroll duration; run that test on a device for hitch measurements.

Launch arguments used by the tests: `-uiTesting` (in-memory store, no orphan sweep), `-seedDemo` (debug builds: build a demo library from `seed.mov`), `-seedLarge` (with `-seedDemo`: add a 240-clip folder), `-noLivePreviews`.

## Project layout

```
project.yml                 XcodeGen spec (app, UI tests, local package)
Packages/RepasoCore/        Swift package: models, rules and maths, unit-tested
  Sources/RepasoCore/
    Model/                  SwiftData models: Folder, Original, Clip
    Library/                LibraryService: every mutation goes through here
    Queries/                folder contents, sorting, reordering
    Storage/                video files and the thumbnail cache
    Playback/               loop timing, player gestures, zoom framing, clip queue
    Cut/                    mark/trim/filmstrip maths
    Preview/                live-preview budget and sources
    Tags/  Import/  Export/  Format/
Repaso/                     the SwiftUI app
  App/  Design/  Components/  Home/  Folder/  Player/  Cut/  Sheets/  Import/  DragDrop/
RepasoUITests/              smoke test and seeded walkthroughs
docs/                       design specs, implementation plans, TestFlight guide
```

The rule of the split: anything with a rule or a number in it lives in `RepasoCore` and is tested without UI. The app holds views, view models and thin AVFoundation/Photos adapters.

## Docs

- Design specs: [core loop](docs/superpowers/specs/2026-10-15-repaso-core-loop-design.md), [drag & drop, share, tags](docs/superpowers/specs/2026-10-16-repaso-drag-share-tags-design.md), [player extras, previews, polish](docs/superpowers/specs/2026-10-16-repaso-player-previews-polish-design.md)
- Implementation plans: [docs/superpowers/plans](docs/superpowers/plans)
- Shipping to TestFlight: [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md)

## Status

Feature-complete for v1. Not yet verified on a physical iPhone: deleting from Photos, share-sheet targets, AirPlay, haptics, and live-preview battery use with large libraries.

Out of scope for v1: iPad/Mac, iCloud sync, search, landscape, playlists, accounts.

## Privacy

Videos are copied into the app's own storage and never leave the phone unless you share a clip. Photos access is used only to import the videos you pick and, if you ask, to delete them from Photos afterwards.
