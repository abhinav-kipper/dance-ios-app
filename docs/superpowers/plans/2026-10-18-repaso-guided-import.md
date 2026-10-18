# Guided Import and Clips-Only Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace "full videos + clips" with clips only, and bring videos in through a step-by-step guide (Make clips? → Cut and name → Keep the full video? → File each clip), with Continue later into Unsorted.

**Architecture:** In RepasoCore, `Recording` (an internal file holder, pending while in the guide or Unsorted) replaces `Original`, and `Clip` carries name, instructors and folder. The guide's step logic is a pure `ImportGuideFlow` value in RepasoCore so it can be unit-tested. The app adds an `ImportGuideModel` plus `ImportGuideView` (a full-screen cover) that reuses the existing cutter, the copy coordinator and the clip exporter.

**Tech Stack:** SwiftUI (iOS 26), Swift 6 strict concurrency, SwiftData, AVFoundation, Swift Testing (RepasoCore), XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-18-repaso-guided-import-design.md`. Read it before any task. Section numbers below (§) refer to it.

## Global Constraints

- Prefix every Xcode or Swift command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Core tests: `cd Packages/RepasoCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.
- App build: `xcodegen generate && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Repaso.xcodeproj -scheme Repaso -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -quiet`. Expect no warnings.
- UI tests: the same command with `test`, plus `-only-testing:RepasoUITests/<Class>` while iterating. Run one test run at a time, never two at once.
- **No commits** unless the owner asks. Each task ends with a checkpoint: tests green, plus `git diff --stat` reviewed.
- Swift 6 strict concurrency, deployment target iOS 26.0, no new dependencies.
- Colours come from `Theme` only: pink (`Theme.rose`) for finding and choosing, green (`Theme.accent`) for doing. All animation goes through `Theme.motion(reduceMotion)`.
- Exact copy (§2): "Make clips", "Use the whole video", "Keep the full video too?", "Keep it", "Delete it", "Your clips stay. They can only be trimmed shorter later.", "Continue later", "Video 2 of 5", "Save clip", "Cancel", "Finish", "3 clips saved" with a "Go to" action, "12 clips from 5 videos", `Create "Hammerlock"`, "Orphans", "Unsorted", "2 clips so far", "Delete the full video? Your N other clips stay. They can only be trimmed shorter later." House voice: no "successfully", no "please".
- Store: a new file `Repaso-v2.store`. On launch, delete the old default store and every file in the video and thumbnail directories that no `Recording` references (§4.4).
- Whole-video tolerance: `0.05` seconds.

## Review Focus

1. **The app is killed mid-guide or mid-export.** On relaunch the video is in Unsorted with every named clip intact, and no new files are left behind. Test in Task 2.
2. **A name made only of spaces.** Save stays disabled, and the core rejects it too. Test in Task 1 (core) and Task 9 (UI).
3. **A picked video fails to copy** (iCloud-only, or no space). The guide skips it with the row's failure message. It must not leave a pending recording with no file. Test in Task 6.
4. **The remembered last folder was deleted.** The folder chip starts empty instead of crashing or pointing at a deleted folder. Test in Task 3 (`ImportGuideFlow.defaultFolder`).
5. **A video resumed from Unsorted gets more clips after "Keep it / Delete it" was answered.** The guide asks again (§4.2). Test in Task 3.

---

### Task 1: Core model swap (Recording replaces Original)

**Files:**
- Create: `Packages/RepasoCore/Sources/RepasoCore/Model/Recording.swift`
- Delete: `Packages/RepasoCore/Sources/RepasoCore/Model/Original.swift`
- Modify:
  - `Model/Clip.swift`
  - `Model/Folder.swift`
  - `Model/RepasoSchema.swift`
  - `Library/LibraryService.swift`
  - `Library/LibraryError.swift`
  - `Queries/FolderContents.swift`
  - `Search/LibrarySearch.swift`
  - `Tags/TagSuggestions.swift`
  - `Preview/PreviewSource.swift`
- Tests: rewrite `ModelTests`, `LibraryServiceTests`, `FolderContentsTests`, `SearchTests`, `LinkTests`, `DragLibraryTests`, `NotesAndInboxTests`. Delete `ClipsFirstTests`; move its still-valid cases into the new `GuidedImportTests.swift`.

**Interfaces:**
- Produces:
  - `@Model Recording` with:
    - `id: UUID`
    - `fileName: String`
    - `duration: Double`
    - `recordedAt: Date?`
    - `importedAt: Date`
    - `photosAssetID: String?`
    - `isPending: Bool = true`
    - `keepWholeVideo: Bool?`
    - `sortIndex: Int`
    - `clips: [Clip]` (cascade)
    - `init(fileName:duration:recordedAt:photosAssetID:sortIndex:importedAt:)`
  - `Clip`:
    - `recording: Recording?` replaces `original`
    - adds `instructors: [String] = []`
    - `init(name:start:end:sortIndex:recording:addedAt:)`
    - `var coversWholeRecording: Bool`: true when `start <= 0.05` and `end >= recording.duration - 0.05`
    - `thumbnailRequest` and `previewSource` use `recording.fileName`
    - `effectiveFolder` and `isFiledElsewhere` are removed; `folder` is the home
  - `Folder`:
    - drops `originals` and `linkedOriginals`
    - adds `isOrphans: Bool = false`
  - `RepasoSchema`:
    - `models = [Folder.self, Recording.self, Clip.self]`
    - `makeContainer(inMemory:)` uses `ModelConfiguration(url: <Application Support>/Repaso-v2.store)` when on disk
    - new `static func removeLegacyStore()` deletes `default.store*` in Application Support
  - `LibraryError` adds `.emptyName`, `.missingFolder`, `.notPending`.
  - `LibraryService` (each method saves):
    - `addRecording(fileName: String, duration: Double, recordedAt: Date?, photosAssetID: String?) throws -> Recording`. The new recording is pending, with `sortIndex` = max + 1.
    - `addClip(to: Recording, name: String, instructors: [String], start: Double, end: Double) throws -> Clip`. Throws `.emptyName` when the name is blank after trimming. Normalises the range with `ClipRange.normalized`. Folder is nil.
    - `addWholeClip(to: Recording, name: String, instructors: [String]) throws -> Clip`
    - `deleteClip(_:)`: when the recording has no clips left and is not pending, also deletes the recording and passes its file to `cleanup`.
    - `place`, `setLinks`, `unlink`, `moveClip`, `dropClip`, `undo`, `setNote(Clip)`, `updateInfo`, `updateRange`, `setFraming`, `toggleFavorite`, `toggleLearned`, `markPlayed`: same signatures for clips. All `Original` overloads are removed.
    - `setInstructors(_ clip: Clip, _ names: [String]) throws`
  - `FolderContents`:
    - keeps `rootFolders`, `subfolders`, `folderClips(in:sort:hideLearned:)`, `clipCount(in:)`, `mosaic(for:limit:)`, `favorites`, `totals`, `sortClips`, `isLinked(_ clip:in:)`
    - all of these ignore clips whose `recording?.isPending == true`
    - removes every `Original` query
    - adds `pendingRecordings(_ ctx: ModelContext) throws -> [Recording]`, ordered by `sortIndex`
  - `LibrarySearch.results(for:clips:folders:)`. `Results` loses `videos`. Matches clip name, instructors, note and folder name, and skips pending clips.
  - `TagSuggestions`:
    - `instructors(for:excluding:in clips: [Clip], limit:)`
    - `names(for query: String, in clips: [Clip], limit: Int = 3) -> [String]`, distinct and prefix matches first
    - `events` is removed

- [ ] **Step 1: Write the failing tests** in `GuidedImportTests.swift`:
  - `addClipNeedsAName`: `addClip(to: r, name: "  ", …)` throws `LibraryError.emptyName`; `"  Backazouk "` is stored as `"Backazouk"`.
  - `wholeClipCoversRecording`: `addWholeClip` → `start == 0`, `end == r.duration`, `coversWholeRecording`; a clip `1...3` on a 120s recording is not whole.
  - `pendingClipsAreHidden`: a clip on a pending recording, filed into `turns`, is absent from `folderClips(in: turns)`, `clipCount`, `favorites` (when ★) and `LibrarySearch.results`.
  - `deletingLastClipRemovesFile`: a non-pending recording with one clip; `deleteClip` → `cleanup` receives the file name and the recording is gone. With two clips, deleting one keeps the file.
  - `nameSuggestions`: clips named "Backazouk", "Back basic", "Pasitos"; `names(for: "Back")` == `["Back basic", "Backazouk"]` (sorted, distinct).

  Then update the other suites to the new API and keep their behaviour assertions (links, drag receipts, notes, sorting, search).

- [ ] **Step 2: Run the core tests.** Expected: compile failure on `Recording`.
- [ ] **Step 3: Implement the model, schema and service changes** listed in Interfaces. `detach` stays as the private building block for Task 2. Remove `normaliseClips`: a clip's `folder` is now always its home.
- [ ] **Step 4: Run the core tests.** Expected: all pass.
- [ ] **Step 5: Checkpoint.** Review `git diff --stat` (the app target is expected not to build until Task 5).

### Task 2: Finish, the export choice, and deleting pending videos (core)

**Files:**
- Modify: `Packages/RepasoCore/Sources/RepasoCore/Library/LibraryService.swift`
- Test: `GuidedImportTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `setKeepWholeVideo(_ r: Recording, _ keep: Bool?) throws`
  - `finish(_ r: Recording, folders: [UUID: Folder]) throws`. Throws `.notPending` if the recording isn't pending, and `.missingFolder` unless every clip id has a folder. Sets each clip's `folder`, then `isPending = false`, then saves once.
  - `struct OwnFile { let clipID: UUID; let fileName: String; let duration: Double }` (public)
  - `adoptOwnFiles(_ files: [OwnFile], from r: Recording) throws`. In one save: each named clip moves to a new `Recording` (`isPending` copied from `r`, `photosAssetID` nil, start 0, end = duration). If `r` has no clips left, it is deleted and its file goes to `cleanup`. This replaces `detach`.
  - `clipsNeedingOwnFiles(_ r: Recording) -> [Clip]`: every clip of `r` except one that covers the whole recording. Used both at Finish when `keepWholeVideo == false`, and when deleting a whole clip that has siblings.
  - `deleteWholeClip(_ clip: Clip, siblingsMovedTo files: [OwnFile]) throws`: `adoptOwnFiles(files)` and deleting the clip together, in one save.
  - `deletePending(_ r: Recording) throws`: deletes the recording, its clips and its file. Throws `.notPending` if it's already filed.

- [ ] **Step 1: Write the failing tests:**
  - `finishNeedsEveryFolder`: two clips; folders for one only → throws `.missingFolder`, and `r.isPending` stays true. With both → not pending, and each clip's `folder` matches.
  - `ownFilesKeepEverything`: a clip with ★, ✓, a note, instructors, a link and folder `turns`. After `adoptOwnFiles`, a new recording holds the clip with `start == 0` and `end == 4`; the old recording is gone and its file was passed to `cleanup`; every field is unchanged.
  - `ownFilesStayPending`: adopting from a pending recording gives pending recordings.
  - `deleteWholeClipKeepsSiblings`: a whole clip plus two others; `deleteWholeClip` with two `OwnFile`s → two recordings of one clip each, the whole clip is gone, and the old file is cleaned up.
  - `deletePendingRemovesAll`: removes the clips and the file; on a filed recording it throws `.notPending`.
  - **Review Focus 1:** `failedExportLeavesNothing`. Call `adoptOwnFiles` with an unknown `clipID`. It throws, nothing changes, and `r` is still pending with its clips. Validate every `clipID` before mutating anything.
- [ ] **Step 2: Run the tests.** Expected: FAIL (symbols missing).
- [ ] **Step 3: Implement** the methods above.
- [ ] **Step 4: Run the core tests.** Expected: PASS.
- [ ] **Step 5: Checkpoint.**

### Task 3: Guide flow logic and the Orphans folder (core)

**Files:**
- Create: `Packages/RepasoCore/Sources/RepasoCore/Import/ImportGuideFlow.swift`
- Modify: `Library/LibraryService.swift` (`deleteFolder`, `orphansFolder`)
- Test: `ImportGuideFlowTests.swift`, `GuidedImportTests.swift`

**Interfaces:**
- Produces:
  - `public enum ImportStep: Equatable, Sendable { case trimChoice, cut, keepWhole, file }`
  - `public struct ImportGuideFlow: Equatable, Sendable`, with:
    - `init(clipCount: Int, hasWholeClip: Bool, keepWholeVideo: Bool?)`
    - `var startStep: ImportStep`: `.cut` if `clipCount > 0` and there is no whole clip yet; `.trimChoice` otherwise
    - `func next(after: ImportStep, usedWholeVideo: Bool) -> ImportStep?`, in this order:
      - `trimChoice`: `.file` if the whole video was used, otherwise `.cut`
      - `cut`: `.keepWhole` when `keepWholeVideo == nil`, otherwise `.file`
      - `keepWhole`: `.file`
      - `file`: nil
    - `func visibleSteps(usedWholeVideo: Bool) -> [ImportStep]`: the dots; steps that don't apply are left out
    - `static func defaultFolder(previousInList: Folder?, lastUsed: Folder?) -> Folder?`: returns `previousInList ?? lastUsed`, and nil when `lastUsed.isDeleted` or its `modelContext` is nil
  - `LibraryService`:
    - `orphansFolder() throws -> Folder`: finds the folder with `isOrphans`, or creates "Orphans" on Home (last in sort order)
    - `deleteFolder(_:mode: .moveContentsUp)` on a top-level folder moves its clips to `orphansFolder()`; on Orphans itself only `.deleteContents` is allowed (throws `.invalidMoveTarget` otherwise)
    - `addClip(to:…)` on a recording whose `keepWholeVideo` is non-nil resets it to nil (Task 1's method gains this rule here)

- [ ] **Step 1: Write the failing tests:**
  - `freshVideoStartsAtTrimChoice`, `resumedWithClipsStartsAtCut`
  - `wholeVideoSkipsToFile`: `next(after: .trimChoice, usedWholeVideo: true) == .file`; its `visibleSteps` == `[.trimChoice, .file]`
  - `answeredKeepSkipsKeepStep`
  - **Review Focus 5:** `newClipsAfterAnswerAskAgain`. `setKeepWholeVideo(r, false)`, then `addClip` → `r.keepWholeVideo == nil`, and a flow built from it gives `next(after: .cut) == .keepWhole`.
  - **Review Focus 4:** `deletedLastFolderGivesNoDefault`. Create a folder, delete it with the service, then `defaultFolder(previousInList: nil, lastUsed: deleted) == nil`.
  - `topLevelDeleteMovesClipsToOrphans`: delete "Turns" (top level) with move-up → its clips are in a folder with `isOrphans`, named "Orphans". A second deletion reuses the same folder. Renaming Orphans and deleting again still reuses it.
  - `nestedDeleteMovesClipsUp`: as today, clips go to the parent, not to Orphans.
  - `orphansOnlyDeletesContents`
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the core tests.** Expected: PASS.
- [ ] **Step 5: Checkpoint.**

### Task 4: Launch, store reset and the app compile pass (no new UI yet)

**Files:**
- Delete: `Repaso/Components/OriginalCard.swift`, `Repaso/Home/VideosView.swift`, `Repaso/Sheets/VideoInfoSheet.swift`, `Repaso/Sheets/DeleteOriginalSheet.swift`, `Repaso/Sheets/MoveSheet.swift` (only if its Move-to-folder use is fully covered by `LinkSheet`; otherwise port it to clips).
- Modify:
  - `Repaso/App/RepasoApp.swift`: on non-UI-test launch, call `RepasoSchema.removeLegacyStore()` before `makeContainer`, then sweep orphan files using the existing `VideoStore.sweepOrphans` with the recordings' file names.
  - `Repaso/App/AppEnvironment.swift`
  - `Repaso/App/DemoSeed.swift`: seed recordings plus named clips in folders, with one pending recording that has one clip, named "Thursday class" in the UI grid by its date title.
  - `Repaso/App/ClipKeeper.swift`: becomes `OwnFileExporter`, see the Interfaces below.
  - `Repaso/Player/PlaybackItem.swift`: clip-only. Either replace the enum with `Clip` at the call sites or keep a single-case wrapper; prefer removing it.
  - `Repaso/Player/PlayerView.swift`: "…" menu loses Edit details and Play full video.
  - `Repaso/Components/ClipRow.swift`: `ClipMenuItems` loses Play full video. Delete calls `OwnFileExporter` when `clip.coversWholeRecording` and siblings exist, with the confirm copy from Global Constraints.
  - `Repaso/Folder/FolderView.swift`, `Repaso/Folder/FolderSupport.swift`: remove the To cut section and the `nil`-folder (Unsorted) mode.
  - `Repaso/Home/HomeView.swift`: remove the Videos tile. The Unsorted tile counts `pendingRecordings` and routes to `Route.unsorted` (the view comes in Task 8; leave a placeholder that compiles).
  - `Repaso/Search/SearchView.swift`: no Videos section.
  - `Repaso/Sheets/LinkSheet.swift`, `Repaso/Cut/CutModel.swift`, `Repaso/Cut/CutView.swift`: work on `Recording`. For Trim…, the cutter opens on `clip.recording` with that clip selected.
  - `Repaso/Import/ImportCoordinator.swift`: creates `Recording`s with `photosAssetID`, and drops the batch tag fields.
  - `Repaso/Import/ImportSheet.swift`: delete it; Task 6 replaces it. Until then, have the Import button open the existing cut flow on the new recording so the app stays usable.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `@MainActor enum OwnFileExporter`, with:
  - `static func export(_ clips: [Clip], env: AppEnvironment, progress: @escaping (Double) -> Void) async throws -> [LibraryService.OwnFile]`. Uses the existing `ClipExporter.export` at HighestQuality into new store file names. On any error, removes the files it already made, then rethrows.
  - `static func sizeText(of r: Recording, env: AppEnvironment) -> String?`

- [ ] **Step 1: Make the app target build.** Command: App build (see Global Constraints). Expected: `** BUILD SUCCEEDED **` with no warnings.
- [ ] **Step 2: Run the existing UI tests that don't touch import:** `SmokeTests`, `PlayerActionsTests`, `LinksAndSearchTests`, `AccessibilityAuditTests`. Fix their seed-dependent queries. Expected: PASS.
- [ ] **Step 3: Delete `KeepClipsTests`** (its flow no longer exists; Task 9 covers deleting the whole clip).
- [ ] **Step 4: Checkpoint.**

### Task 5: Guide model and shell (steps, dots, queue, Continue later)

**Files:**
- Create:
  - `Repaso/Import/Guide/ImportGuideModel.swift`
  - `Repaso/Import/Guide/ImportGuideView.swift`
  - `Repaso/Import/Guide/StepDots.swift`
  - `Repaso/Import/Guide/TrimChoiceStep.swift`
- Modify:
  - `Repaso/Home/HomeView.swift` and `Repaso/Folder/FolderView.swift`: the import entry points present `ImportGuideView` as a `fullScreenCover`.
  - `Repaso/Import/ImportCoordinator.swift`: keeps copying files in order. It exposes `recordingID(for item:)` and a per-item `state` so the guide can wait on the current video.

**Interfaces:**
- Consumes: `ImportGuideFlow`, `ImportStep`, `ImportCoordinator`, the `LibraryService` methods from Tasks 1–3.
- Produces: `@Observable @MainActor final class ImportGuideModel`, with:
  - `init(coordinatorItems: [ImportCoordinator.Item.ID]?, resuming: Recording?, env: AppEnvironment, context: ModelContext)`
  - `var position: (index: Int, count: Int)`, which drives "Video 2 of 5" (hidden when `count == 1`)
  - `var current: Recording?`, which is nil while the current file is still copying
  - `private(set) var step: ImportStep`
  - `var usedWholeVideo: Bool`
  - `var lastInstructors: [String]`, seeded from the newest clip's instructors
  - `@ObservationIgnored @AppStorage("import.lastFolderID") var lastFolderID: String?`
  - `func useWholeVideo(name: String, instructors: [String]) throws`
  - `func startCutting()`
  - `func saveClip(name: String, instructors: [String], range: ClosedRange<Double>) throws -> Clip`
  - `func doneCutting()`
  - `func keepWholeVideo(name: String, instructors: [String]) throws`
  - `func dropWholeVideo() throws`
  - `var folderChoices: [UUID: Folder]`
  - `func setFolder(_ f: Folder, for clipID: UUID)`
  - `func finish() async throws`: runs the `OwnFileExporter` export when `keepWholeVideo == false`, then `finish(r, folders:)`, then moves on to the next video or ends
  - `func continueLater()`
  - `var finishedThisSession: [Recording]`, used for the toast and the Photos offer
  - `var isFinishing: Bool`
  - `var exportProgress: Double?`

- [ ] **Step 1: Build the shell.**
  - A cover with "Continue later" at top-left (pink), `StepDots` at top centre, and "Video 2 of 5" beside it.
  - The step body switches on `model.step`, with the right-to-left slide (`.transition(.push(from: .trailing))` under `Theme.motion`).
  - `TrimChoiceStep`: the video plays with sound through the existing player layer view, plus two large buttons, "Make clips" (green fill) and "Use the whole video" (pink outline).
  - While `current == nil`, show the poster with a slim progress line from the coordinator item.
- [ ] **Step 2: Wire Continue later.** It dismisses the cover. The current video and the ones left stay pending, so they appear in Unsorted. Interrupted copies continue in the coordinator as today. **Review Focus 3:** an item whose copy `.failed` is skipped, with a toast showing the failure message, and no recording is created for it.
- [ ] **Step 3: Run the app build.** Expected: success with no warnings.
- [ ] **Step 4: Checkpoint.**

### Task 6: Cut step and the name card

**Files:**
- Create: `Repaso/Import/Guide/NameCard.swift`, `Repaso/Import/Guide/CutStep.swift`
- Modify: `Repaso/Cut/CutView.swift`, `Repaso/Cut/CutModel.swift`, `Repaso/Cut/ClipTray.swift`

**Interfaces:**
- Consumes: `ImportGuideModel.saveClip`, `.doneCutting`, `.lastInstructors`; `TagSuggestions.names` and `.instructors`.
- Produces:
  - `struct NameCard: View`, with:
    - `init(title: String, initialName: String, instructors: [String], suggestionsFrom clips: [Clip], onSave: (String, [String]) -> Void, onCancel: () -> Void)`
    - The Save button's accessibility identifier is `"saveClip"`; the name field's is `"clipName"`.
  - `CutView` gains an `onClipMarked: ((ClosedRange<Double>) -> Void)?` hook. When set, Mark end calls it after the pink flash instead of creating the clip itself. `CutStep` uses the hook; Trim… keeps today's behaviour.

- [ ] **Step 1: Add the hook to `CutView`.**
  - The guide's Mark end plays the pink flash, pauses the video on the range's first frame and springs the `NameCard` up.
  - **Save clip** calls `model.saveClip`, then the new clip springs into the strip.
  - **Cancel** drops the range.
  - **Done** shows once there is at least one clip and calls `doneCutting()`.
- [ ] **Step 2: Build `NameCard`.**
  - Name is required: Save is disabled while the trimmed name is empty, and return saves.
  - Name suggestion chips show the first 3 matches from `TagSuggestions.names`.
  - Instructors are on one comma line, prefilled from `lastInstructors`, with suggestion chips.
  - The card's style follows the import sheet's tag field style.
- [ ] **Step 3: Run the app build.** Expected: success.
- [ ] **Step 4: Checkpoint.**

### Task 7: Keep-whole step, file step and folder search picker

**Files:**
- Create:
  - `Repaso/Import/Guide/KeepWholeStep.swift`
  - `Repaso/Import/Guide/FileStep.swift`
  - `Repaso/Sheets/FolderSearchPicker.swift`
- Modify: `Repaso/Sheets/NewFolderRow.swift`, which gains an `initialName: String` parameter and a `label` override for `Create "X"`.

**Interfaces:**
- Consumes: `ImportGuideModel.keepWholeVideo`, `.dropWholeVideo`, `.setFolder`, `.finish`, `ImportGuideFlow.defaultFolder`.
- Produces: `struct FolderSearchPicker: View`, with:
  - `init(selected: Folder?, onPick: (Folder) -> Void)`
  - a search field whose accessibility identifier is `"folderSearch"`
  - matches shown with their path (`"Turns › Hammerlock"`)
  - when nothing matches, the first row reads `Create "<query>"`

- [ ] **Step 1: Build `KeepWholeStep`.**
  - The poster sits above the title "Keep the full video too?".
  - "Keep it" opens the `NameCard` titled "Name the full video", prefilled with the date title (selected).
  - "Delete it" has the quiet line below it.
- [ ] **Step 2: Build `FileStep`.**
  - One row per clip of `current`: poster, name, and a folder chip.
  - Chip defaults come from `ImportGuideFlow.defaultFolder(previousInList:lastUsed:)`, top to bottom.
  - A chip pulses pink when it's set.
  - "Finish" (green) is enabled once every clip has a folder.
  - While `isFinishing`: a progress line from `exportProgress`, a green check, then on to the next video or close.
  - On close: the toast ("3 clips saved", or "12 clips from 5 videos" for a batch) with "Go to", then the Photos offer for the `photosAssetID`s in `finishedThisSession`, reusing `PhotosCleaner`.
  - On an export error: a toast with the error text, and the video stays at `.file`, still pending.
- [ ] **Step 3: Run the app build.** Expected: success.
- [ ] **Step 4: Checkpoint.**

### Task 8: Unsorted, Orphans in the UI, onboarding copy

**Files:**
- Create: `Repaso/Home/UnsortedView.swift`
- Modify:
  - `Repaso/Home/HomeView.swift`
  - `Repaso/App/Route.swift`
  - `Repaso/Home/GuideView.swift`
  - `Repaso/Folder/FolderView.swift`: the delete-folder confirm text says "Its clips go to Orphans" when the folder is top-level.

**Interfaces:**
- Consumes: `FolderContents.pendingRecordings`, `LibraryService.deletePending`, `ImportGuideModel(resuming:)`.

- [ ] **Step 1: Build `UnsortedView`.**
  - A 2-column grid of pending recordings: the poster, its date title, and "2 clips so far" when it has clips.
  - Tap opens `ImportGuideView` resuming that recording.
  - Long-press shows a Delete action with a confirm, which calls `deletePending`.
  - The Home tile shows only while the count is greater than 0, labelled "Unsorted · N".
- [ ] **Step 2: Rewrite the onboarding cards.**
  - Cards 0–1 become one card, "Bring in your class videos": pick → make clips or use the whole video → name each → file each, and Continue later puts it in Unsorted.
  - Card 3 loses the loop and pause line.
  - Card 4 says clips can be in several folders through Folders….
- [ ] **Step 3: Run the app build.** Expected: success.
- [ ] **Step 4: Checkpoint.**

### Task 9: UI tests, walkthrough and device install

**Files:**
- Create: `RepasoUITests/GuidedImportTests.swift`
- Modify:
  - `RepasoUITests/WalkthroughTests.swift`
  - `RepasoUITests/GuideAndNotesTests.swift`
  - `RepasoUITests/NavigationAndCutTests.swift`
  - `RepasoUITests/DeckHelpers.swift`
  - `Repaso/App/DemoSeed.swift`: add a `-seedImport` launch argument that adds two pending recordings from `seed.mov` and opens the guide on both, as if they had been picked. The Photos picker can't be driven in XCUITest.

**Tests:**
- `testUseWholeVideoNameAndFile`:
  - "Use the whole video", then type "Backazouk".
  - The Save button stays disabled until a non-space character is typed. **This is Review Focus 2:** type `"   "` first and assert Save is not enabled.
  - Pick a folder through the search, then Finish.
  - The clip shows in that folder and plays.
- `testMakeTwoClipsDeleteFullVideoThenFile`:
  - Make clips, Mark start/end twice and name both, then Done.
  - "Delete it", file both, Finish.
  - Both clips play, and no "Video file missing" appears.
- `testContinueLaterThenResume`:
  - With 2 queued videos: name one clip in video 1, then Continue later.
  - The Unsorted tile reads "Unsorted · 2".
  - Open video 1: it starts at the cut step, its clip is in the strip, and it shows "1 clip so far".
- `testCreateFolderFromSearch`: typing "Sabado" in the folder search shows `Create "Sabado"`; tapping it sets the chip.
- `testDeleteTopLevelFolderSendsClipsToOrphans`.
- Walkthrough updated for the new import and the removed Videos tile.

- [ ] **Step 1: Write the tests.**
- [ ] **Step 2: Run them.** Expected: FAIL until the seeds and identifiers line up. Fix the app code, not the assertions.
- [ ] **Step 3: Run the full suites.** Core: all pass. UI: all pass in a single run.
- [ ] **Step 4: Install on both phones** (if connected). Then do a real import of 2 videos with Continue later, and a long-video "Delete it" export.
- [ ] **Step 5: Checkpoint**, and report to the owner with the test output. Commit only when asked.
