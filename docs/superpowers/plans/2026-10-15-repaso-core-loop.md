# Repaso Sub-project A (Core loop) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a TestFlight-ready iOS 26 SwiftUI app that imports class videos, cuts them into clips, files them in folders, and plays clips instantly with slow-motion and looping.

**Architecture:** A local Swift package `RepasoCore` holds the SwiftData models and every rule with a number or a decision in it (library mutations, queries, loop logic, cut math, formatting, file storage, thumbnails, metadata), tested with Swift Testing on macOS. The `Repaso` app target holds SwiftUI screens, `@Observable` view models, and thin AVFoundation/PhotosUI adapters. XcodeGen generates the Xcode project from `project.yml`.

**Tech Stack:** Swift 6, SwiftUI (iOS 26, Liquid Glass), SwiftData, AVFoundation, PhotosUI, ImageIO, Swift Testing, XCUITest, XcodeGen 2.46.

**Spec:** `docs/superpowers/specs/2026-10-15-repaso-core-loop-design.md` (visual values: `~/Documents/UK_VISA_DOCS/repaso-handoff/HANDOFF.md` §4–§6)

## Global Constraints

- Deployment target **iOS 26.0**, iPhone only, portrait only, dark appearance forced. Package also builds for **macOS 26.0** (tests only).
- No third-party runtime dependencies.
- Swift 6 language mode, strict concurrency complete.
- Colours: bg `#030303` (player `#000000`), text `#F5F5F7`, secondary white 72%, accent `#BFFF3C`, onAccent `#0A0A0A`, rose `#FF4D8D`, primary button white 93% with `#0A0A0A` text.
- Touch targets ≥ 44×44pt everywhere; every icon-only button has an `accessibilityLabel`.
- No double-tap gesture anywhere in the app.
- Clip minimum length **0.5s**; note max **140** chars; filmstrip window **40s**; chrome idle **2.4s**; toast with Undo **3.8s**; "Clip N added" toast **2.2s**.
- Speeds exactly `0.5, 0.75, 1.0`; persisted under `@AppStorage("playbackSpeed")`; `audioTimePitchAlgorithm = .timeDomain`.
- Timecodes: `03:41.2` (precise), `3:21` (range), `0:08` (duration), `4.2s` (length), all SF Mono.
- All library mutations go through `LibraryService`; views never call `context.delete` directly.
- **Git:** the user's global rule is *never commit unless explicitly asked*. Each task ends with a checkpoint (`git status` + `git diff --stat`) instead of a commit.

## Review Focus

1. **Moving an original into a folder that already holds one of its moved clips** → the clip must show once (under its original), not twice. Test: `normalisesClipWhenOriginalJoinsItsFolder` (Task 3).
2. **Marking end before start** (user scrubbed back while recording) → range swaps, never negative. Test: `markSwapsReversedRange` (Task 5).
3. **Very short videos (< 40s, < 0.5s)** → filmstrip window shrinks to the video; clip range clamps to the duration. Tests: `windowShrinksForShortVideo`, `normalizedClampsToTinyDuration` (Task 5).
4. **Moving a folder into its own descendant** → rejected with `LibraryError.invalidMoveTarget`. Test: `rejectsMoveIntoDescendant` (Task 3).
5. **Deleting a folder whose contents include an original with clips filed elsewhere** → those clips are deleted too (cascade), and video files are removed only after save. Test: `deleteContentsCascadesClipsFiledElsewhere` (Task 3).

---

## File map

```
project.yml
Packages/RepasoCore/Package.swift
Packages/RepasoCore/Sources/RepasoCore/
  Model/Folder.swift, Original.swift, Clip.swift, RepasoSchema.swift, ThumbnailRequest.swift
  Format/TimeFormat.swift
  Library/LibraryService.swift, LibraryError.swift
  Queries/FolderContents.swift, ClipSort.swift
  Playback/LoopController.swift
  Cut/ClipRange.swift, CutSession.swift
  Storage/VideoStore.swift, ThumbnailStore.swift
  Import/VideoMetadata.swift
Packages/RepasoCore/Tests/RepasoCoreTests/
  Support/TestContainer.swift, TestVideo.swift
  TimeFormatTests.swift, LibraryServiceTests.swift, FolderContentsTests.swift,
  LoopControllerTests.swift, CutTests.swift, StorageTests.swift, VideoMetadataTests.swift
Repaso/
  App/RepasoApp.swift, AppEnvironment.swift, Route.swift
  Design/Theme.swift, Glass.swift, PressableButtonStyle.swift
  Components/PosterView.swift, ClipRow.swift, OriginalCard.swift, FolderCard.swift, Toast.swift, FloatingPill.swift
  Home/HomeView.swift
  Folder/FolderView.swift, FolderToolbar.swift
  Import/ImportCoordinator.swift, VideoTransfer.swift, ImportSheet.swift
  Sheets/MoveSheet.swift, ClipInfoSheet.swift, DeleteOriginalSheet.swift, DeleteFolderSheet.swift
  Player/PlayerView.swift, PlayerModel.swift, PlayerLayerView.swift, SpeedControl.swift
  Cut/CutView.swift, CutModel.swift, Filmstrip.swift, ClipTray.swift
  Resources/Info.plist, Assets.xcassets/
RepasoUITests/SmokeTests.swift
```

---

### Task 0: Toolchain gate (manual, user)

**Blocking.** Current CLT install is broken (compiler 6.2.3.3.21 vs SDK 6.2.3.3.2).

- [ ] **Step 1:** Install Xcode 26 from the App Store, open it once, and accept the license and component install (including the iOS 26 simulator).
- [ ] **Step 2:** Run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
- [ ] **Step 3: Verify**

Run: `xcodebuild -version && swift --version && xcrun simctl list devices available | grep iPhone | head -3`
Expected: `Xcode 26.x`, a Swift version matching the Xcode toolchain, at least one iPhone simulator.

---

### Task 1: Scaffold project, package, and TimeFormat

**Files:**
- Create: `project.yml`, `Packages/RepasoCore/Package.swift`, `Packages/RepasoCore/Sources/RepasoCore/Format/TimeFormat.swift`, `Packages/RepasoCore/Tests/RepasoCoreTests/TimeFormatTests.swift`, `Repaso/App/RepasoApp.swift` (placeholder root view), `Repaso/Resources/Assets.xcassets/{Contents.json,AppIcon.appiconset/Contents.json,AccentColor.colorset/Contents.json}`, `RepasoUITests/SmokeTests.swift` (empty class), `.gitignore`

**Interfaces:**
- Produces: `TimeFormat.precise(_:) -> String`, `TimeFormat.range(_:) -> String`, `TimeFormat.duration(_:) -> String`, `TimeFormat.length(_:) -> String`

- [ ] **Step 1: Create `Packages/RepasoCore/Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RepasoCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "RepasoCore", targets: ["RepasoCore"])],
    targets: [
        .target(name: "RepasoCore"),
        .testTarget(name: "RepasoCoreTests", dependencies: ["RepasoCore"]),
    ]
)
```

- [ ] **Step 2: Write the failing test** `TimeFormatTests.swift`

```swift
import Testing
@testable import RepasoCore

struct TimeFormatTests {
    @Test func precise() {
        #expect(TimeFormat.precise(221.2) == "03:41.2")
        #expect(TimeFormat.precise(768) == "12:48.0")
        #expect(TimeFormat.precise(59.96) == "01:00.0")
        #expect(TimeFormat.precise(-3) == "00:00.0")
    }
    @Test func range() {
        #expect(TimeFormat.range(201.9) == "3:21")
        #expect(TimeFormat.range(0) == "0:00")
    }
    @Test func duration() {
        #expect(TimeFormat.duration(8.4) == "0:08")
        #expect(TimeFormat.duration(65.6) == "1:06")
    }
    @Test func length() {
        #expect(TimeFormat.length(4.23) == "4.2s")
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd Packages/RepasoCore && swift test --filter TimeFormatTests`
Expected: FAIL — `cannot find 'TimeFormat' in scope`

- [ ] **Step 4: Implement `TimeFormat.swift`**

```swift
import Foundation

public enum TimeFormat {
    /// `03:41.2` — Cut mode playhead.
    public static func precise(_ t: Double) -> String {
        let tenths = Int((max(0, t) * 10).rounded())
        let minutes = tenths / 600
        let seconds = Double(tenths % 600) / 10
        return String(format: "%02d:%04.1f", minutes, seconds)
    }
    /// `3:21` — clip ranges, filmstrip labels (floors).
    public static func range(_ t: Double) -> String {
        let s = Int(max(0, t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    /// `0:08` — durations (rounds).
    public static func duration(_ t: Double) -> String {
        let s = Int(max(0, t).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    /// `4.2s` — clip lengths.
    public static func length(_ t: Double) -> String {
        String(format: "%.1fs", max(0, t))
    }
}
```

- [ ] **Step 5: Run to verify it passes** — same command. Expected: 4 tests passed.

- [ ] **Step 6: Create `project.yml`**

```yaml
name: Repaso
options:
  bundleIdPrefix: com.amudgal
  deploymentTarget:
    iOS: "26.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    TARGETED_DEVICE_FAMILY: "1"
    DEVELOPMENT_TEAM: ""          # set your Team ID before device/TestFlight builds
    CODE_SIGN_STYLE: Automatic
packages:
  RepasoCore:
    path: Packages/RepasoCore
targets:
  Repaso:
    type: application
    platform: iOS
    sources: [Repaso]
    dependencies:
      - package: RepasoCore
    info:
      path: Repaso/Resources/Info.plist
      properties:
        CFBundleDisplayName: Repaso
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        UILaunchScreen:
          UIColorName: LaunchBackground
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        UIRequiresFullScreen: true
        UIUserInterfaceStyle: Dark
        NSPhotoLibraryUsageDescription: "Repaso imports your class videos so you can cut and practice clips."
        ITSAppUsesNonExemptEncryption: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.amudgal.repaso
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
  RepasoUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [RepasoUITests]
    dependencies:
      - target: Repaso
schemes:
  Repaso:
    build:
      targets:
        Repaso: all
    test:
      targets:
        - RepasoUITests
        - package: RepasoCore/RepasoCoreTests
```

Add `LaunchBackground.colorset` (`#030303`) and `AccentColor.colorset` (`#BFFF3C`) to the asset catalog. `.gitignore`: `*.xcodeproj/`, `.build/`, `DerivedData/`, `.DS_Store`, `xcuserdata/`.

- [ ] **Step 7: Minimal app** `Repaso/App/RepasoApp.swift`

```swift
import SwiftUI

@main
struct RepasoApp: App {
    var body: some Scene {
        WindowGroup { Text("Repaso").preferredColorScheme(.dark) }
    }
}
```

`RepasoUITests/SmokeTests.swift`: `import XCTest; final class SmokeTests: XCTestCase {}`

- [ ] **Step 8: Generate and build**

Run: `git init -q 2>/dev/null; xcodegen generate && xcodebuild build -project Repaso.xcodeproj -scheme Repaso -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: `** BUILD SUCCEEDED **` (with `-quiet`: no error output, exit 0).

- [ ] **Step 9: Checkpoint** — `git status --short`. No commit.

---

### Task 2: SwiftData models and schema

**Files:**
- Create: `Model/Folder.swift`, `Model/Original.swift`, `Model/Clip.swift`, `Model/RepasoSchema.swift`, `Model/ThumbnailRequest.swift`, `Tests/.../Support/TestContainer.swift`, `Tests/.../ModelTests.swift`

**Interfaces:**
- Produces: `Folder(name:sortIndex:parent:)`, `Original(title:fileName:duration:recordedAt:folder:)`, `Clip(name:start:end:sortIndex:original:)`, `Folder.isDescendant(of:) -> Bool`, `Folder.ancestors: [Folder]` (root first), `Clip.length: Double`, `Clip.isFiledElsewhere: Bool`, `RepasoSchema.makeContainer(inMemory:) throws -> ModelContainer`, `ThumbnailRequest(id:fileName:time:)`, `Original.thumbnailRequest`, `Clip.thumbnailRequest?`

- [ ] **Step 1: Write the failing test** `ModelTests.swift` and `Support/TestContainer.swift`

```swift
// Support/TestContainer.swift
import SwiftData
@testable import RepasoCore

@MainActor
func makeContext() throws -> ModelContext {
    try RepasoSchema.makeContainer(inMemory: true).mainContext
}
```

```swift
// ModelTests.swift
import Testing
import SwiftData
@testable import RepasoCore

@MainActor
struct ModelTests {
    @Test func cascadeDeletesClips() throws {
        let ctx = try makeContext()
        let o = Original(title: "Class", fileName: "a.mov", duration: 60, recordedAt: nil, folder: nil)
        ctx.insert(o)
        let c = Clip(name: "Clip 1", start: 1, end: 3, sortIndex: 0, original: o)
        ctx.insert(c)
        try ctx.save()
        ctx.delete(o)
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<Clip>()) == 0)
    }

    @Test func descendantCheck() throws {
        let ctx = try makeContext()
        let a = Folder(name: "A", sortIndex: 0)
        let b = Folder(name: "B", sortIndex: 0, parent: a)
        let c = Folder(name: "C", sortIndex: 0, parent: b)
        [a, b, c].forEach(ctx.insert)
        #expect(c.isDescendant(of: a))
        #expect(!a.isDescendant(of: c))
        #expect(c.ancestors.map(\.name) == ["A", "B"])
    }

    @Test func thumbnailTimes() throws {
        let o = Original(title: "x", fileName: "x.mov", duration: 100, recordedAt: nil, folder: nil)
        #expect(o.thumbnailRequest.time == 30)
        let c = Clip(name: "c", start: 10, end: 20, sortIndex: 0, original: o)
        #expect(c.thumbnailRequest?.time == 13)
        #expect(c.thumbnailRequest?.fileName == "x.mov")
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter ModelTests`. Expected: FAIL, `cannot find 'Original'`.

- [ ] **Step 3: Implement models**

```swift
// Model/Folder.swift
import Foundation
import SwiftData

@Model
public final class Folder {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var sortIndex: Int
    public var createdAt: Date
    public var parent: Folder?
    @Relationship(deleteRule: .nullify, inverse: \Folder.parent) public var children: [Folder] = []
    @Relationship(deleteRule: .nullify, inverse: \Original.folder) public var originals: [Original] = []
    @Relationship(deleteRule: .nullify, inverse: \Clip.folder) public var looseClips: [Clip] = []

    public init(name: String, sortIndex: Int, parent: Folder? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.sortIndex = sortIndex
        self.parent = parent
        self.createdAt = createdAt
    }

    /// Root first, excluding self.
    public var ancestors: [Folder] {
        var chain: [Folder] = []
        var cursor = parent
        while let f = cursor { chain.insert(f, at: 0); cursor = f.parent }
        return chain
    }

    public func isDescendant(of other: Folder) -> Bool {
        ancestors.contains { $0.id == other.id }
    }
}
```

```swift
// Model/Original.swift
import Foundation
import SwiftData

@Model
public final class Original {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var fileName: String
    public var importedAt: Date
    public var recordedAt: Date?
    public var duration: Double
    public var instructors: [String] = []
    public var event: String?
    public var folder: Folder?
    public var nextClipNumber: Int = 1
    @Relationship(deleteRule: .cascade, inverse: \Clip.original) public var clips: [Clip] = []

    public init(title: String, fileName: String, duration: Double, recordedAt: Date?, folder: Folder?, importedAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.fileName = fileName
        self.duration = duration
        self.recordedAt = recordedAt
        self.folder = folder
        self.importedAt = importedAt
    }

    public var thumbnailRequest: ThumbnailRequest {
        ThumbnailRequest(id: id, fileName: fileName, time: duration * 0.3)
    }
}
```

```swift
// Model/Clip.swift
import Foundation
import SwiftData

@Model
public final class Clip {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var start: Double
    public var end: Double
    public var note: String?
    public var isFavorite: Bool = false
    public var isLearned: Bool = false
    public var lastPlayedAt: Date?
    public var addedAt: Date
    public var sortIndex: Int
    public var zoom: Double = 1
    public var panX: Double = 0
    public var panY: Double = 0
    public var original: Original?
    public var folder: Folder?

    public init(name: String, start: Double, end: Double, sortIndex: Int, original: Original, addedAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.start = start
        self.end = end
        self.sortIndex = sortIndex
        self.original = original
        self.addedAt = addedAt
    }

    public var length: Double { end - start }

    /// True when the clip has been filed in a folder other than its original's.
    public var isFiledElsewhere: Bool {
        guard let folder else { return false }
        return folder.id != original?.folder?.id
    }

    public var thumbnailRequest: ThumbnailRequest? {
        guard let original else { return nil }
        return ThumbnailRequest(id: id, fileName: original.fileName, time: start + (end - start) * 0.3)
    }
}
```

```swift
// Model/ThumbnailRequest.swift
import Foundation

public struct ThumbnailRequest: Hashable, Sendable {
    public let id: UUID
    public let fileName: String
    public let time: Double
    public init(id: UUID, fileName: String, time: Double) {
        self.id = id; self.fileName = fileName; self.time = time
    }
}
```

```swift
// Model/RepasoSchema.swift
import SwiftData

public enum RepasoSchema {
    public static let models: [any PersistentModel.Type] = [Folder.self, Original.self, Clip.self]

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: Schema(models), configurations: config)
    }
}
```

- [ ] **Step 4: Run to verify it passes** — Expected: 3 tests passed.
- [ ] **Step 5: Checkpoint** — `git status --short`.

---

### Task 3: LibraryService (all mutations and rules)

**Files:**
- Create: `Library/LibraryError.swift`, `Library/LibraryService.swift`, `Cut/ClipRange.swift`, `Tests/.../LibraryServiceTests.swift`

**Interfaces:**
- Consumes: models from Task 2.
- Produces (all `@MainActor`, all `throws`, all save on success):
  - `LibraryService(context: ModelContext, cleanup: FileCleanup? = nil)` where `typealias FileCleanup = @MainActor (_ fileNames: [String], _ thumbnailIDs: [UUID]) -> Void`
  - `createFolder(named: String, in parent: Folder?) -> Folder`
  - `renameFolder(_: Folder, to: String)`
  - `moveFolder(_: Folder, to parent: Folder?)`
  - `reorderFolder(_: Folder, by offset: Int)` (−1 = up, +1 = down)
  - `deleteFolder(_: Folder, mode: FolderDeleteMode)` with `enum FolderDeleteMode { case deleteContents, moveContentsUp }`
  - `addOriginal(title: String, fileName: String, duration: Double, recordedAt: Date?, to: Folder?) -> Original`
  - `moveOriginal(_: Original, to: Folder?)`
  - `deleteOriginal(_: Original)`
  - `addClip(to: Original, start: Double, end: Double) -> Clip`
  - `updateRange(_: Clip, start: Double, end: Double)`
  - `updateInfo(_: Clip, name: String, note: String)`
  - `moveClip(_: Clip, to: Folder?)` (nil = "With its video")
  - `toggleFavorite(_: Clip)`, `toggleLearned(_: Clip)`, `markPlayed(_: Clip, at: Date)`
  - `deleteClip(_: Clip)`
  - `ClipRange.normalized(start:end:duration:minLength:) -> ClosedRange<Double>`, `ClipRange.minLength = 0.5`
  - `LibraryService.noteLimit = 140`

- [ ] **Step 1: Write the failing tests** `LibraryServiceTests.swift`

```swift
import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct LibraryServiceTests {
    final class Removed { var files: [String] = [] }   // per-test instance: Swift Testing runs tests in parallel

    let ctx: ModelContext
    let lib: LibraryService
    let removedBox = Removed()
    var removed: [String] { removedBox.files }

    init() throws {
        ctx = try makeContext()
        let box = removedBox
        lib = LibraryService(context: ctx) { files, _ in box.files += files }
    }

    func original(_ title: String = "Class", in folder: Folder? = nil, duration: Double = 120) throws -> Original {
        try lib.addOriginal(title: title, fileName: "\(title).mov", duration: duration, recordedAt: nil, to: folder)
    }

    // Folders
    @Test func createFolderInsertsAtTopWithDefaultName() throws {
        let a = try lib.createFolder(named: "Turns", in: nil)
        let b = try lib.createFolder(named: "   ", in: nil)
        #expect(b.name == "New folder")
        #expect(b.sortIndex == 0)
        #expect(a.sortIndex == 1)
    }

    @Test func rejectsMoveIntoDescendant() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: a)
        #expect(throws: LibraryError.invalidMoveTarget) { try lib.moveFolder(a, to: b) }
        #expect(throws: LibraryError.invalidMoveTarget) { try lib.moveFolder(a, to: a) }
    }

    @Test func reorderSwapsWithNeighbour() throws {
        let a = try lib.createFolder(named: "A", in: nil)   // ends at index 1
        let b = try lib.createFolder(named: "B", in: nil)   // index 0
        try lib.reorderFolder(b, by: 1)
        #expect(a.sortIndex == 0 && b.sortIndex == 1)
        try lib.reorderFolder(b, by: 1)                     // already last: no-op
        #expect(b.sortIndex == 1)
    }

    @Test func deleteContentsCascadesClipsFiledElsewhere() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let sub = try lib.createFolder(named: "Sub", in: turns)
        let other = try lib.createFolder(named: "Other", in: nil)
        let o = try original("Thursday", in: sub)
        let c = try lib.addClip(to: o, start: 1, end: 4)
        try lib.moveClip(c, to: other)
        try lib.deleteFolder(turns, mode: .deleteContents)
        #expect(try ctx.fetchCount(FetchDescriptor<Folder>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<Original>()) == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<Clip>()) == 0)
        #expect(removed == ["Thursday.mov"])
    }

    @Test func moveContentsUpToRoot() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let sub = try lib.createFolder(named: "Sub", in: turns)
        let o = try original("Thursday", in: turns)
        let elsewhere = try original("Saturday", in: nil)
        let loose = try lib.addClip(to: elsewhere, start: 0, end: 2)
        try lib.moveClip(loose, to: turns)
        try lib.deleteFolder(turns, mode: .moveContentsUp)
        #expect(sub.parent == nil)
        #expect(o.folder == nil)
        #expect(loose.folder == nil)
        #expect(removed.isEmpty)
    }

    @Test func moveContentsUpToParent() throws {
        let home = try lib.createFolder(named: "Home2", in: nil)
        let turns = try lib.createFolder(named: "Turns", in: home)
        let o = try original("Thursday", in: turns)
        try lib.deleteFolder(turns, mode: .moveContentsUp)
        #expect(o.folder?.id == home.id)
    }

    // Originals
    @Test func deleteOriginalRemovesClipsAndFile() throws {
        let other = try lib.createFolder(named: "Other", in: nil)
        let o = try original()
        let c = try lib.addClip(to: o, start: 0, end: 1)
        try lib.moveClip(c, to: other)
        try lib.deleteOriginal(o)
        #expect(try ctx.fetchCount(FetchDescriptor<Clip>()) == 0)
        #expect(other.looseClips.isEmpty)
        #expect(removed == ["Class.mov"])
    }

    @Test func normalisesClipWhenOriginalJoinsItsFolder() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o = try original()
        let c = try lib.addClip(to: o, start: 0, end: 1)
        try lib.moveClip(c, to: turns)
        #expect(c.isFiledElsewhere)
        try lib.moveOriginal(o, to: turns)
        #expect(c.folder == nil)
        #expect(!c.isFiledElsewhere)
    }

    // Clips
    @Test func clipNamesAreMonotonic() throws {
        let o = try original()
        let c1 = try lib.addClip(to: o, start: 0, end: 1)
        let c2 = try lib.addClip(to: o, start: 2, end: 3)
        try lib.deleteClip(c2)
        let c3 = try lib.addClip(to: o, start: 4, end: 5)
        #expect([c1.name, c3.name] == ["Clip 1", "Clip 3"])
        #expect(c3.sortIndex > c1.sortIndex)
    }

    @Test func addClipNormalisesRange() throws {
        let o = try original(duration: 10)
        let c = try lib.addClip(to: o, start: 9.9, end: 9.8)
        #expect(c.start == 9.5 && c.end == 10)
    }

    @Test func moveClipBackToItsVideo() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o = try original()
        let c = try lib.addClip(to: o, start: 0, end: 1)
        try lib.moveClip(c, to: turns)
        try lib.moveClip(c, to: nil)
        #expect(c.folder == nil)
        try lib.moveClip(c, to: turns)
        try lib.moveOriginal(o, to: nil)
        try lib.moveClip(c, to: nil)
        #expect(c.folder == nil)
    }

    @Test func infoTrimsAndCapsNote() throws {
        let c = try lib.addClip(to: try original(), start: 0, end: 1)
        try lib.updateInfo(c, name: "  ", note: String(repeating: "a", count: 200))
        #expect(c.name == "Clip 1")      // empty name keeps old name
        #expect(c.note?.count == 140)
        try lib.updateInfo(c, name: "Hammerlock", note: "   ")
        #expect(c.name == "Hammerlock")
        #expect(c.note == nil)
    }

    @Test func togglesAndPlayed() throws {
        let c = try lib.addClip(to: try original(), start: 0, end: 1)
        try lib.toggleFavorite(c); try lib.toggleLearned(c)
        #expect(c.isFavorite && c.isLearned)
        let now = Date(timeIntervalSince1970: 100)
        try lib.markPlayed(c, at: now)
        #expect(c.lastPlayedAt == now)
    }

    @Test func normalizedClampsToTinyDuration() {
        #expect(ClipRange.normalized(start: 0, end: 0.1, duration: 0.3) == 0...0.3)
        #expect(ClipRange.normalized(start: 5, end: 2, duration: 10) == 2...5)
        #expect(ClipRange.normalized(start: -1, end: 0.2, duration: 10) == 0...0.5)
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter LibraryServiceTests`. Expected: FAIL, `cannot find 'LibraryService'`.

- [ ] **Step 3: Implement**

```swift
// Library/LibraryError.swift
public enum LibraryError: Error, Equatable {
    case invalidMoveTarget
}
```

```swift
// Cut/ClipRange.swift
public enum ClipRange {
    public static let minLength = 0.5

    /// Orders the endpoints, clamps them to [0, duration], and enforces `minLength`
    /// (or the whole video when it is shorter than `minLength`).
    public static func normalized(start: Double, end: Double, duration: Double, minLength: Double = minLength) -> ClosedRange<Double> {
        let d = max(0, duration)
        var a = min(max(0, min(start, end)), d)
        var b = min(max(0, max(start, end)), d)
        if b - a < minLength {
            b = min(a + minLength, d)
            a = max(0, b - minLength)
        }
        return a...b
    }
}
```

```swift
// Library/LibraryService.swift
import Foundation
import SwiftData
import os

public enum FolderDeleteMode: Sendable { case deleteContents, moveContentsUp }

@MainActor
public struct LibraryService {
    public typealias FileCleanup = @MainActor (_ fileNames: [String], _ thumbnailIDs: [UUID]) -> Void
    public static let noteLimit = 140
    public static let defaultFolderName = "New folder"

    public let context: ModelContext
    private let cleanup: FileCleanup?
    private let log = Logger(subsystem: "com.amudgal.repaso", category: "library")

    public init(context: ModelContext, cleanup: FileCleanup? = nil) {
        self.context = context
        self.cleanup = cleanup
    }

    // MARK: Folders

    @discardableResult
    public func createFolder(named name: String, in parent: Folder?) throws -> Folder {
        for sibling in try siblings(of: parent) { sibling.sortIndex += 1 }
        let folder = Folder(name: Self.cleanName(name) ?? Self.defaultFolderName, sortIndex: 0, parent: parent)
        context.insert(folder)
        try save()
        return folder
    }

    public func renameFolder(_ folder: Folder, to name: String) throws {
        folder.name = Self.cleanName(name) ?? folder.name
        try save()
    }

    public func moveFolder(_ folder: Folder, to parent: Folder?) throws {
        if let parent, parent.id == folder.id || parent.isDescendant(of: folder) {
            throw LibraryError.invalidMoveTarget
        }
        folder.sortIndex = (try siblings(of: parent).map(\.sortIndex).max() ?? -1) + 1
        folder.parent = parent
        try save()
    }

    public func reorderFolder(_ folder: Folder, by offset: Int) throws {
        let ordered = try siblings(of: folder.parent).sorted { $0.sortIndex < $1.sortIndex }
        guard let i = ordered.firstIndex(where: { $0.id == folder.id }) else { return }
        let j = i + offset
        guard ordered.indices.contains(j) else { return }
        var reordered = ordered
        reordered.swapAt(i, j)
        for (index, f) in reordered.enumerated() { f.sortIndex = index }
        try save()
    }

    public func deleteFolder(_ folder: Folder, mode: FolderDeleteMode) throws {
        switch mode {
        case .deleteContents:
            var files: [String] = []
            var thumbs: [UUID] = []
            collectAndDelete(folder, files: &files, thumbs: &thumbs)
            try save()
            if !files.isEmpty || !thumbs.isEmpty { cleanup?(files, thumbs) }
        case .moveContentsUp:
            let target = folder.parent
            var next = (try siblings(of: target).map(\.sortIndex).max() ?? -1) + 1
            for child in folder.children.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                child.parent = target
                child.sortIndex = next
                next += 1
            }
            for original in folder.originals { original.folder = target }
            for clip in folder.looseClips { clip.folder = target }
            normaliseClips(in: folder.originals + folder.looseClips.compactMap(\.original))
            context.delete(folder)
            try save()
        }
    }

    private func collectAndDelete(_ folder: Folder, files: inout [String], thumbs: inout [UUID]) {
        for child in folder.children { collectAndDelete(child, files: &files, thumbs: &thumbs) }
        for original in folder.originals {
            files.append(original.fileName)
            thumbs.append(original.id)
            thumbs.append(contentsOf: original.clips.map(\.id))
            context.delete(original)
        }
        // Skip clips whose original is being deleted in this pass (cascade handles them).
        for clip in folder.looseClips where !(clip.original.map { o in files.contains(o.fileName) } ?? false) {
            thumbs.append(clip.id)
            context.delete(clip)
        }
        context.delete(folder)
    }

    // MARK: Originals

    @discardableResult
    public func addOriginal(title: String, fileName: String, duration: Double, recordedAt: Date?, to folder: Folder?) throws -> Original {
        let original = Original(title: title, fileName: fileName, duration: duration, recordedAt: recordedAt, folder: folder)
        context.insert(original)
        try save()
        return original
    }

    public func moveOriginal(_ original: Original, to folder: Folder?) throws {
        original.folder = folder
        normaliseClips(in: [original])
        try save()
    }

    public func deleteOriginal(_ original: Original) throws {
        let file = original.fileName
        let thumbs = [original.id] + original.clips.map(\.id)
        context.delete(original)
        try save()
        cleanup?([file], thumbs)
    }

    // MARK: Clips

    @discardableResult
    public func addClip(to original: Original, start: Double, end: Double) throws -> Clip {
        let range = ClipRange.normalized(start: start, end: end, duration: original.duration)
        let number = original.nextClipNumber
        original.nextClipNumber += 1
        let sortIndex = (original.clips.map(\.sortIndex).max() ?? -1) + 1
        let clip = Clip(name: "Clip \(number)", start: range.lowerBound, end: range.upperBound, sortIndex: sortIndex, original: original)
        context.insert(clip)
        try save()
        return clip
    }

    public func updateRange(_ clip: Clip, start: Double, end: Double) throws {
        let range = ClipRange.normalized(start: start, end: end, duration: clip.original?.duration ?? end)
        clip.start = range.lowerBound
        clip.end = range.upperBound
        try save()
        cleanup?([], [clip.id])   // poster is stale
    }

    public func updateInfo(_ clip: Clip, name: String, note: String) throws {
        clip.name = Self.cleanName(name) ?? clip.name
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        clip.note = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.noteLimit))
        try save()
    }

    public func moveClip(_ clip: Clip, to folder: Folder?) throws {
        clip.folder = folder
        if let original = clip.original { normaliseClips(in: [original]) }
        try save()
    }

    public func toggleFavorite(_ clip: Clip) throws { clip.isFavorite.toggle(); try save() }
    public func toggleLearned(_ clip: Clip) throws { clip.isLearned.toggle(); try save() }
    public func markPlayed(_ clip: Clip, at date: Date = .now) throws { clip.lastPlayedAt = date; try save() }

    public func deleteClip(_ clip: Clip) throws {
        let id = clip.id
        context.delete(clip)
        try save()
        cleanup?([], [id])
    }

    // MARK: Helpers

    /// A clip filed in the same folder as its original "lives with its video".
    private func normaliseClips(in originals: [Original]) {
        for original in originals {
            for clip in original.clips where clip.folder != nil && clip.folder?.id == original.folder?.id {
                clip.folder = nil
            }
        }
    }

    private func siblings(of parent: Folder?) throws -> [Folder] {
        if let parent { return parent.children }
        return try context.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.parent == nil }))
    }

    private func save() throws {
        do { try context.save() } catch {
            log.error("save failed: \(error.localizedDescription)")
            context.rollback()
            throw error
        }
    }

    static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

Note on `moveContentsUp` to root: `clip.folder = target` with `target == nil` yields `folder = nil`, which is "with its video" — matches spec §4.

- [ ] **Step 4: Run to verify it passes** — Expected: all `LibraryServiceTests` pass. If `#Predicate { $0.parent == nil }` fails at runtime on a self-referential optional, replace with fetching all folders and filtering `parent == nil` in memory (library sizes are small), and re-run.
- [ ] **Step 5: Checkpoint.**

---

### Task 4: Queries (folder contents, sorting, counts, mosaic)

**Files:**
- Create: `Queries/ClipSort.swift`, `Queries/FolderContents.swift`, `Tests/.../FolderContentsTests.swift`

**Interfaces:**
- Consumes: models, `LibraryService` (tests only).
- Produces:
  - `enum ClipSort: String, CaseIterable, Sendable { case manual, name, dateAdded, recentlyPlayed }` with `title: String`
  - `FolderContents.rootFolders(_ ctx: ModelContext) throws -> [Folder]` (by sortIndex)
  - `FolderContents.subfolders(of: Folder) -> [Folder]` (by sortIndex)
  - `FolderContents.unsortedOriginals(_ ctx:) throws -> [Original]`
  - `FolderContents.originals(in: Folder, sort: ClipSort) -> [Original]`
  - `FolderContents.looseClips(in: Folder, sort: ClipSort, hideLearned: Bool) -> [Clip]`
  - `FolderContents.clips(of: Original, sort: ClipSort, hideLearned: Bool) -> [Clip]`
  - `FolderContents.favorites(_ ctx:, sort: ClipSort) throws -> [Clip]`
  - `FolderContents.playQueue(originals: [Original], loose: [Clip], sort: ClipSort, hideLearned: Bool) -> [Clip]`
  - `FolderContents.clipCount(in: Folder) -> Int` (recursive: clips of originals in it + loose clips filed elsewhere-in, plus all subfolders)
  - `FolderContents.mosaic(for: Folder, limit: Int = 4) -> [ThumbnailRequest]`
  - `FolderContents.totals(_ ctx:) throws -> (clips: Int, folders: Int)`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct FolderContentsTests {
    let ctx: ModelContext
    let lib: LibraryService
    init() throws { ctx = try makeContext(); lib = LibraryService(context: ctx) }

    @Test func originalsVersusLooseClips() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o1 = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: turns)
        let o2 = try lib.addOriginal(title: "Sat", fileName: "s.mov", duration: 60, recordedAt: nil, to: nil)
        _ = try lib.addClip(to: o1, start: 0, end: 1)
        let loose = try lib.addClip(to: o2, start: 0, end: 1)
        try lib.moveClip(loose, to: turns)
        #expect(FolderContents.originals(in: turns, sort: .manual).map(\.title) == ["Thu"])
        #expect(FolderContents.looseClips(in: turns, sort: .manual, hideLearned: false).map(\.id) == [loose.id])
        #expect(try FolderContents.unsortedOriginals(ctx).map(\.title) == ["Sat"])
        // Original still lists its moved clip
        #expect(FolderContents.clips(of: o2, sort: .manual, hideLearned: false).count == 1)
    }

    @Test func sortsAndHidesLearned() throws {
        let o = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: nil)
        let a = try lib.addClip(to: o, start: 0, end: 1)
        let b = try lib.addClip(to: o, start: 2, end: 3)
        let c = try lib.addClip(to: o, start: 4, end: 5)
        try lib.updateInfo(a, name: "Zeta", note: "")
        try lib.updateInfo(b, name: "Alpha", note: "")
        a.addedAt = .init(timeIntervalSince1970: 1); b.addedAt = .init(timeIntervalSince1970: 3); c.addedAt = .init(timeIntervalSince1970: 2)
        try lib.markPlayed(c, at: .init(timeIntervalSince1970: 50))
        try lib.toggleLearned(b)
        #expect(FolderContents.clips(of: o, sort: .manual, hideLearned: false).map(\.name) == ["Zeta", "Alpha", "Clip 3"])
        #expect(FolderContents.clips(of: o, sort: .name, hideLearned: false).map(\.name) == ["Alpha", "Clip 3", "Zeta"])
        #expect(FolderContents.clips(of: o, sort: .dateAdded, hideLearned: false).map(\.name) == ["Alpha", "Clip 3", "Zeta"])
        #expect(FolderContents.clips(of: o, sort: .recentlyPlayed, hideLearned: false).first?.name == "Clip 3")
        #expect(FolderContents.clips(of: o, sort: .manual, hideLearned: true).map(\.name) == ["Zeta", "Clip 3"])
    }

    @Test func recursiveCountsAndTotals() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let sub = try lib.createFolder(named: "Sub", in: turns)
        let o = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: sub)
        let c1 = try lib.addClip(to: o, start: 0, end: 1)
        _ = try lib.addClip(to: o, start: 2, end: 3)
        try lib.moveClip(c1, to: turns)
        // turns: loose c1 + sub's original's clips (c1 counted once, c2) = 2
        #expect(FolderContents.clipCount(in: turns) == 2)
        #expect(FolderContents.clipCount(in: sub) == 2)
        let totals = try FolderContents.totals(ctx)
        #expect(totals.clips == 2 && totals.folders == 2)
    }

    @Test func playQueueOrder() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: turns)
        let a = try lib.addClip(to: o, start: 0, end: 1)
        let other = try lib.addOriginal(title: "Sat", fileName: "s.mov", duration: 60, recordedAt: nil, to: nil)
        let l = try lib.addClip(to: other, start: 0, end: 1)
        try lib.moveClip(l, to: turns)
        let q = FolderContents.playQueue(
            originals: FolderContents.originals(in: turns, sort: .manual),
            loose: FolderContents.looseClips(in: turns, sort: .manual, hideLearned: false),
            sort: .manual, hideLearned: false)
        #expect(q.map(\.id) == [a.id, l.id])
    }

    @Test func mosaicPrefersClipsThenOriginals() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let o = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: turns)
        let c = try lib.addClip(to: o, start: 0, end: 10)
        let m = FolderContents.mosaic(for: turns)
        #expect(m.first?.id == c.id)
        #expect(m.count == 2)          // clip + original poster
        let empty = try lib.createFolder(named: "Empty", in: nil)
        #expect(FolderContents.mosaic(for: empty).isEmpty)
    }

    @Test func favorites() throws {
        let o = try lib.addOriginal(title: "Thu", fileName: "t.mov", duration: 60, recordedAt: nil, to: nil)
        let a = try lib.addClip(to: o, start: 0, end: 1)
        _ = try lib.addClip(to: o, start: 2, end: 3)
        try lib.toggleFavorite(a)
        #expect(try FolderContents.favorites(ctx, sort: .manual).map(\.id) == [a.id])
    }
}
```

- [ ] **Step 2: Run to verify it fails** — `swift test --filter FolderContentsTests`. Expected: FAIL.

- [ ] **Step 3: Implement**

```swift
// Queries/ClipSort.swift
public enum ClipSort: String, CaseIterable, Sendable {
    case manual, name, dateAdded, recentlyPlayed

    public var title: String {
        switch self {
        case .manual: "Manual"
        case .name: "Name"
        case .dateAdded: "Date added"
        case .recentlyPlayed: "Recently played"
        }
    }
}
```

```swift
// Queries/FolderContents.swift
import Foundation
import SwiftData

@MainActor
public enum FolderContents {
    public static func rootFolders(_ ctx: ModelContext) throws -> [Folder] {
        try ctx.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.parent == nil },
                                              sortBy: [SortDescriptor(\.sortIndex)]))
    }

    public static func subfolders(of folder: Folder) -> [Folder] {
        folder.children.sorted { $0.sortIndex < $1.sortIndex }
    }

    public static func unsortedOriginals(_ ctx: ModelContext) throws -> [Original] {
        let all = try ctx.fetch(FetchDescriptor<Original>(predicate: #Predicate { $0.folder == nil }))
        return sortOriginals(all, by: .manual)
    }

    public static func originals(in folder: Folder, sort: ClipSort) -> [Original] {
        sortOriginals(folder.originals, by: sort)
    }

    public static func looseClips(in folder: Folder, sort: ClipSort, hideLearned: Bool) -> [Clip] {
        let loose = folder.looseClips.filter { $0.original != nil && $0.original?.folder?.id != folder.id }
        return sortClips(filter(loose, hideLearned: hideLearned), by: sort)
    }

    public static func clips(of original: Original, sort: ClipSort, hideLearned: Bool) -> [Clip] {
        sortClips(filter(original.clips, hideLearned: hideLearned), by: sort)
    }

    public static func favorites(_ ctx: ModelContext, sort: ClipSort) throws -> [Clip] {
        let favs = try ctx.fetch(FetchDescriptor<Clip>(predicate: #Predicate { $0.isFavorite }))
        return sortClips(favs.filter { $0.original != nil }, by: sort)
    }

    public static func playQueue(originals: [Original], loose: [Clip], sort: ClipSort, hideLearned: Bool) -> [Clip] {
        originals.flatMap { clips(of: $0, sort: sort, hideLearned: hideLearned) } + loose
    }

    /// Clips listed anywhere inside `folder` (recursively), each counted once.
    public static func clipCount(in folder: Folder) -> Int {
        var ids = Set<UUID>()
        collectClipIDs(folder, into: &ids)
        return ids.count
    }

    private static func collectClipIDs(_ folder: Folder, into ids: inout Set<UUID>) {
        for o in folder.originals { o.clips.forEach { ids.insert($0.id) } }
        folder.looseClips.forEach { ids.insert($0.id) }
        folder.children.forEach { collectClipIDs($0, into: &ids) }
    }

    /// Up to `limit` posters: clips first (newest first), then originals, recursing into subfolders.
    public static func mosaic(for folder: Folder, limit: Int = 4) -> [ThumbnailRequest] {
        var out: [ThumbnailRequest] = []
        var queue: [Folder] = [folder]
        while !queue.isEmpty, out.count < limit {
            let f = queue.removeFirst()
            let clips = (f.originals.flatMap(\.clips) + f.looseClips).sorted { $0.addedAt > $1.addedAt }
            out += clips.compactMap(\.thumbnailRequest)
            out += f.originals.map(\.thumbnailRequest)
            queue += subfolders(of: f)
        }
        var seen = Set<UUID>()
        return Array(out.filter { seen.insert($0.id).inserted }.prefix(limit))
    }

    public static func totals(_ ctx: ModelContext) throws -> (clips: Int, folders: Int) {
        (try ctx.fetchCount(FetchDescriptor<Clip>()), try ctx.fetchCount(FetchDescriptor<Folder>()))
    }

    // MARK: Sorting

    static func filter(_ clips: [Clip], hideLearned: Bool) -> [Clip] {
        hideLearned ? clips.filter { !$0.isLearned } : clips
    }

    static func sortClips(_ clips: [Clip], by sort: ClipSort) -> [Clip] {
        switch sort {
        case .manual:
            clips.sorted { ($0.sortIndex, $0.addedAt) < ($1.sortIndex, $1.addedAt) }
        case .name:
            clips.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateAdded:
            clips.sorted { $0.addedAt > $1.addedAt }
        case .recentlyPlayed:
            clips.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        }
    }

    static func sortOriginals(_ originals: [Original], by sort: ClipSort) -> [Original] {
        switch sort {
        case .name:
            originals.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        default:
            originals.sorted { ($0.recordedAt ?? $0.importedAt) > ($1.recordedAt ?? $1.importedAt) }
        }
    }
}
```

`Date` tuples are not `Comparable` via `<` on tuples with `Date`? — tuples of `Comparable` elements up to arity 6 support `<`; `Int` and `Date` are both `Comparable`, so `($0.sortIndex, $0.addedAt) < (...)` compiles.

- [ ] **Step 4: Run to verify it passes.**
- [ ] **Step 5: Checkpoint.**

---

### Task 5: LoopController and CutSession (pure logic)

**Files:**
- Create: `Playback/LoopController.swift`, `Cut/CutSession.swift`, `Tests/.../LoopControllerTests.swift`, `Tests/.../CutTests.swift`

**Interfaces:**
- Produces:
  - `struct LoopController { var loopEnabled: Bool = true; var gap: Gap = .none; func actionAtEnd() -> EndAction; mutating func cycleGap() }`, `enum Gap: Int { none = 0, one = 1, two = 2; var label: String }` ("No pause", "1s pause", "2s pause"), `enum EndAction: Equatable { case restart, restartAfter(Double), stop }`
  - `struct CutSession { let duration: Double; private(set) var markStart: Double?; var isRecording: Bool; mutating func mark(at: Double) -> ClosedRange<Double>?; mutating func cancelMark(); func liveLength(at: Double) -> Double? }`
  - `CutSession.windowLength(for duration: Double) -> Double`, `CutSession.windowStart(center: Double, duration: Double) -> Double`, `CutSession.x(for time: Double, windowStart: Double, windowLength: Double, width: Double) -> Double`, `CutSession.time(forX: Double, windowStart: Double, windowLength: Double, width: Double) -> Double`, `CutSession.trimStart(_ range: ClosedRange<Double>, to: Double) -> ClosedRange<Double>`, `CutSession.trimEnd(_ range: ClosedRange<Double>, to: Double, duration: Double) -> ClosedRange<Double>`

- [ ] **Step 1: Write the failing tests**

```swift
// LoopControllerTests.swift
import Testing
@testable import RepasoCore

struct LoopControllerTests {
    @Test func defaultsRestart() {
        #expect(LoopController().actionAtEnd() == .restart)
    }
    @Test func gapCyclesAndDelays() {
        var l = LoopController()
        l.cycleGap(); #expect(l.gap == .one); #expect(l.actionAtEnd() == .restartAfter(1))
        l.cycleGap(); #expect(l.gap == .two); #expect(l.gap.label == "2s pause")
        l.cycleGap(); #expect(l.gap == .none); #expect(l.gap.label == "No pause")
    }
    @Test func loopOffStops() {
        var l = LoopController(); l.loopEnabled = false; l.gap = .two
        #expect(l.actionAtEnd() == .stop)
    }
}
```

```swift
// CutTests.swift
import Foundation
import Testing
@testable import RepasoCore

struct CutTests {
    @Test func markCreatesRange() {
        var s = CutSession(duration: 768)
        #expect(s.mark(at: 200) == nil)
        #expect(s.isRecording)
        #expect(s.liveLength(at: 204.2) == 4.2.rounded(toPlaces: 1))
        #expect(s.mark(at: 208) == 200...208)
        #expect(!s.isRecording)
    }
    @Test func markSwapsReversedRange() {
        var s = CutSession(duration: 768)
        _ = s.mark(at: 210)
        #expect(s.mark(at: 205) == 205...210)
    }
    @Test func markEnforcesMinimum() {
        var s = CutSession(duration: 768)
        _ = s.mark(at: 10)
        #expect(s.mark(at: 10.1) == 10...10.5)
    }
    @Test func windowCentresAndClamps() {
        #expect(CutSession.windowStart(center: 221, duration: 768) == 201)
        #expect(CutSession.windowStart(center: 5, duration: 768) == 0)
        #expect(CutSession.windowStart(center: 767, duration: 768) == 728)
    }
    @Test func windowShrinksForShortVideo() {
        #expect(CutSession.windowLength(for: 12) == 12)
        #expect(CutSession.windowStart(center: 6, duration: 12) == 0)
    }
    @Test func xTimeRoundTrip() {
        let x = CutSession.x(for: 211, windowStart: 201, windowLength: 40, width: 350)
        #expect(x == 87.5)
        #expect(CutSession.time(forX: 87.5, windowStart: 201, windowLength: 40, width: 350) == 211)
    }
    @Test func trimHandlesKeepMinimum() {
        #expect(CutSession.trimStart(200...208, to: 207.9) == 207.5...208)
        #expect(CutSession.trimStart(200...208, to: -4) == 0...208)
        #expect(CutSession.trimEnd(200...208, to: 200.1, duration: 768) == 200...200.5)
        #expect(CutSession.trimEnd(200...208, to: 900, duration: 768) == 200...768)
    }
}

extension Double {
    func rounded(toPlaces p: Int) -> Double {
        let m = pow(10, Double(p)); return (self * m).rounded() / m
    }
}
```

`liveLength` returns a value rounded to 0.1 (display value), so the comparison is exact.

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement**

```swift
// Playback/LoopController.swift
public struct LoopController: Equatable, Sendable {
    public enum Gap: Int, CaseIterable, Sendable {
        case none = 0, one = 1, two = 2
        public var seconds: Double { Double(rawValue) }
        public var label: String { self == .none ? "No pause" : "\(rawValue)s pause" }
    }
    public enum EndAction: Equatable, Sendable { case restart, restartAfter(Double), stop }

    public var loopEnabled = true
    public var gap: Gap = .none
    public init() {}

    public func actionAtEnd() -> EndAction {
        guard loopEnabled else { return .stop }
        return gap == .none ? .restart : .restartAfter(gap.seconds)
    }

    public mutating func cycleGap() {
        gap = Gap(rawValue: (gap.rawValue + 1) % Gap.allCases.count) ?? .none
    }
}
```

```swift
// Cut/CutSession.swift
import Foundation

public struct CutSession: Equatable, Sendable {
    public static let maxWindow = 40.0

    public let duration: Double
    public private(set) var markStart: Double?

    public init(duration: Double) { self.duration = duration }

    public var isRecording: Bool { markStart != nil }

    /// First call starts recording and returns nil; second returns the finished range.
    public mutating func mark(at t: Double) -> ClosedRange<Double>? {
        guard let start = markStart else { markStart = min(max(0, t), duration); return nil }
        markStart = nil
        return ClipRange.normalized(start: start, end: t, duration: duration)
    }

    public mutating func cancelMark() { markStart = nil }

    public func liveLength(at t: Double) -> Double? {
        guard let start = markStart else { return nil }
        return (abs(t - start) * 10).rounded() / 10
    }

    // MARK: Filmstrip geometry

    public static func windowLength(for duration: Double) -> Double { min(maxWindow, max(0, duration)) }

    public static func windowStart(center: Double, duration: Double) -> Double {
        let w = windowLength(for: duration)
        return max(0, min(duration - w, center - w / 2))
    }

    public static func x(for time: Double, windowStart: Double, windowLength: Double, width: Double) -> Double {
        guard windowLength > 0 else { return 0 }
        return (time - windowStart) / windowLength * width
    }

    public static func time(forX x: Double, windowStart: Double, windowLength: Double, width: Double) -> Double {
        guard width > 0 else { return windowStart }
        return windowStart + x / width * windowLength
    }

    public static func trimStart(_ range: ClosedRange<Double>, to t: Double) -> ClosedRange<Double> {
        let start = min(max(0, t), range.upperBound - ClipRange.minLength)
        return max(0, start)...range.upperBound
    }

    public static func trimEnd(_ range: ClosedRange<Double>, to t: Double, duration: Double) -> ClosedRange<Double> {
        let end = max(min(duration, t), range.lowerBound + ClipRange.minLength)
        return range.lowerBound...min(end, duration)
    }
}
```

- [ ] **Step 4: Run to verify they pass.**
- [ ] **Step 5: Checkpoint.**

---

### Task 6: VideoStore, ThumbnailStore, VideoMetadata

**Files:**
- Create: `Storage/VideoStore.swift`, `Storage/ThumbnailStore.swift`, `Import/VideoMetadata.swift`, `Tests/.../Support/TestVideo.swift`, `Tests/.../StorageTests.swift`, `Tests/.../VideoMetadataTests.swift`

**Interfaces:**
- Produces:
  - `struct VideoStore: Sendable { init(directory: URL); static func appDefault() throws -> VideoStore; func url(for fileName: String) -> URL; func adopt(fileAt: URL) throws -> String; func remove(fileName: String); func sweepOrphans(keeping: Set<String>) -> [String]; func fileSize(_ fileName: String) -> Int64? }`
  - `actor ThumbnailStore { init(directory: URL, videos: VideoStore); static func appDefault(videos: VideoStore) throws -> ThumbnailStore; func image(for: ThumbnailRequest, maxPixel: Int = 400) async -> CGImage?; func remove(ids: [UUID]) }`
  - `enum VideoMetadata { static func load(_ url: URL) async throws -> (duration: Double, recordedAt: Date?) }`
  - Test helper `TestVideo.make(seconds: Double, in: URL) async throws -> URL` (H.264 `.mov`, 64×64, 10 fps)

- [ ] **Step 1: Write the test helper and failing tests**

```swift
// Support/TestVideo.swift
import AVFoundation
import CoreVideo

enum TestVideo {
    static func make(seconds: Double, in dir: URL) async throws -> URL {
        let url = dir.appendingPathComponent("\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let frames = Int(seconds * 10)
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(i * 4 % 255), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

```swift
// StorageTests.swift
import Testing
import Foundation
@testable import RepasoCore

struct StorageTests {
    @Test func adoptMovesFileWithExtension() throws {
        let root = try TestVideo.tempDir()
        let store = VideoStore(directory: root.appendingPathComponent("Videos"))
        let src = root.appendingPathComponent("IMG_0001.MOV")
        try Data([1, 2, 3]).write(to: src)
        let name = try store.adopt(fileAt: src)
        #expect(name.hasSuffix(".mov"))
        #expect(FileManager.default.fileExists(atPath: store.url(for: name).path))
        #expect(!FileManager.default.fileExists(atPath: src.path))
        #expect(store.fileSize(name) == 3)
    }

    @Test func sweepRemovesOnlyOrphans() throws {
        let root = try TestVideo.tempDir()
        let store = VideoStore(directory: root)
        for n in ["keep.mov", "orphan.mov"] { try Data([0]).write(to: root.appendingPathComponent(n)) }
        #expect(store.sweepOrphans(keeping: ["keep.mov"]) == ["orphan.mov"])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("keep.mov").path))
    }

    @Test func thumbnailGeneratedThenCachedOnDisk() async throws {
        let root = try TestVideo.tempDir()
        let videos = VideoStore(directory: root.appendingPathComponent("Videos"))
        let src = try await TestVideo.make(seconds: 2, in: root)
        let name = try videos.adopt(fileAt: src)
        let thumbsDir = root.appendingPathComponent("Thumbs")
        let thumbs = ThumbnailStore(directory: thumbsDir, videos: videos)
        let req = ThumbnailRequest(id: UUID(), fileName: name, time: 0.6)
        let image = await thumbs.image(for: req)
        #expect(image != nil)
        #expect(FileManager.default.fileExists(atPath: thumbsDir.appendingPathComponent("\(req.id).jpg").path))
        await thumbs.remove(ids: [req.id])
        #expect(!FileManager.default.fileExists(atPath: thumbsDir.appendingPathComponent("\(req.id).jpg").path))
    }

    @Test func missingVideoGivesNilThumbnail() async throws {
        let root = try TestVideo.tempDir()
        let thumbs = ThumbnailStore(directory: root, videos: VideoStore(directory: root))
        #expect(await thumbs.image(for: ThumbnailRequest(id: UUID(), fileName: "nope.mov", time: 1)) == nil)
    }
}
```

```swift
// VideoMetadataTests.swift
import Testing
@testable import RepasoCore

struct VideoMetadataTests {
    @Test func readsDuration() async throws {
        let url = try await TestVideo.make(seconds: 2, in: try TestVideo.tempDir())
        let meta = try await VideoMetadata.load(url)
        #expect(abs(meta.duration - 2) < 0.2)
    }
}
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement**

```swift
// Storage/VideoStore.swift
import Foundation
import os

public struct VideoStore: Sendable {
    public let directory: URL
    private static let log = Logger(subsystem: "com.amudgal.repaso", category: "videos")

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func appDefault() throws -> VideoStore {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return VideoStore(directory: docs.appendingPathComponent("Videos", isDirectory: true))
    }

    public func url(for fileName: String) -> URL { directory.appendingPathComponent(fileName) }

    /// Moves (or copies, if moving fails) `source` into the store under a fresh UUID name.
    public func adopt(fileAt source: URL) throws -> String {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        let dest = url(for: name)
        do {
            try FileManager.default.moveItem(at: source, to: dest)
        } catch {
            try FileManager.default.copyItem(at: source, to: dest)
        }
        return name
    }

    public func remove(fileName: String) {
        do { try FileManager.default.removeItem(at: url(for: fileName)) }
        catch { Self.log.error("remove \(fileName) failed: \(error.localizedDescription)") }
    }

    @discardableResult
    public func sweepOrphans(keeping referenced: Set<String>) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let orphans = names.filter { !referenced.contains($0) && !$0.hasPrefix(".") }.sorted()
        orphans.forEach(remove(fileName:))
        return orphans
    }

    public func fileSize(_ fileName: String) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url(for: fileName).path)[.size] as? NSNumber)?.int64Value
    }
}
```

```swift
// Storage/ThumbnailStore.swift
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public actor ThumbnailStore {
    private let directory: URL
    private let videos: VideoStore
    private let memory = NSCache<NSUUID, CGImageBox>()

    public init(directory: URL, videos: VideoStore) {
        self.directory = directory
        self.videos = videos
        memory.countLimit = 300
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func appDefault(videos: VideoStore) throws -> ThumbnailStore {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return ThumbnailStore(directory: caches.appendingPathComponent("Thumbnails", isDirectory: true), videos: videos)
    }

    public func image(for request: ThumbnailRequest, maxPixel: Int = 400) async -> CGImage? {
        if let hit = memory.object(forKey: request.id as NSUUID) { return hit.image }
        let file = fileURL(request.id)
        if let image = Self.decode(file) {
            memory.setObject(CGImageBox(image), forKey: request.id as NSUUID)
            return image
        }
        let video = videos.url(for: request.fileName)
        guard FileManager.default.fileExists(atPath: video.path) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: request.time, preferredTimescale: 600)) else { return nil }
        Self.writeJPEG(image, to: file)
        memory.setObject(CGImageBox(image), forKey: request.id as NSUUID)
        return image
    }

    public func remove(ids: [UUID]) {
        for id in ids {
            memory.removeObject(forKey: id as NSUUID)
            try? FileManager.default.removeItem(at: fileURL(id))
        }
    }

    private func fileURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id).jpg") }

    private static func decode(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}

final class CGImageBox: @unchecked Sendable {   // immutable wrapper for NSCache
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
```

```swift
// Import/VideoMetadata.swift
import AVFoundation

public enum VideoMetadata {
    public static func load(_ url: URL) async throws -> (duration: Double, recordedAt: Date?) {
        let asset = AVURLAsset(url: url)
        let (duration, creation) = try await asset.load(.duration, .creationDate)
        let recordedAt = try? await creation?.load(.dateValue)
        return (duration.seconds.isFinite ? duration.seconds : 0, recordedAt ?? nil)
    }
}
```

- [ ] **Step 4: Run to verify they pass** — `swift test`. Expected: all suites pass.
- [ ] **Step 5: Checkpoint.**

---

### Task 7: App shell, design system, environment

**Files:**
- Create: `Repaso/App/AppEnvironment.swift`, `Repaso/App/Route.swift`, `Repaso/Design/Theme.swift`, `Repaso/Design/Glass.swift`, `Repaso/Design/PressableButtonStyle.swift`, `Repaso/Components/PosterView.swift`, `Repaso/Components/Toast.swift`, `Repaso/Components/FloatingPill.swift`
- Modify: `Repaso/App/RepasoApp.swift`

**Interfaces:**
- Consumes: `RepasoSchema`, `VideoStore`, `ThumbnailStore`, `LibraryService`.
- Produces:
  - `@Observable @MainActor final class AppEnvironment { let videos: VideoStore; let thumbnails: ThumbnailStore; var toast: ToastState?; func library(_ ctx: ModelContext) -> LibraryService; func showToast(_ text: String, undo: (() -> Void)?) ; func sweepOrphans(_ ctx: ModelContext) }` injected via `.environment(env)`
  - `enum Route: Hashable { case folder(UUID), unsorted, favorites }`
  - `Theme` constants (spec §4 values), `Theme.spring`, `View.cardGlass(radius:)`, `View.controlGlass(in:)`, `View.panelGlass(radius:)`, `PressableButtonStyle`, `PosterView(request: ThumbnailRequest?, cornerRadius: CGFloat)`, `ToastView`, `FloatingPill(title:systemImage:action:)`

- [ ] **Step 1: Implement Theme and Glass**

```swift
// Design/Theme.swift
import SwiftUI

enum Theme {
    static let bg = Color(red: 3/255, green: 3/255, blue: 3/255)
    static let textPrimary = Color(red: 245/255, green: 245/255, blue: 247/255)
    static let textSecondary = Color.white.opacity(0.72)
    static let accent = Color(red: 191/255, green: 1, blue: 60/255)
    static let onAccent = Color(red: 10/255, green: 10/255, blue: 10/255)
    static let accentTint = accent.opacity(0.15)
    static let rose = Color(red: 1, green: 77/255, blue: 141/255)
    static let roseTint = rose.opacity(0.17)
    static let primaryButton = Color.white.opacity(0.93)
    static let gutter: CGFloat = 20

    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.7)

    enum Radius {
        static let folderCard: CGFloat = 24, listCard: CGFloat = 22, mosaic: CGFloat = 17
        static let thumb: CGFloat = 9, panel: CGFloat = 32, sheet: CGFloat = 38
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static let sectionLabel = Font.system(size: 13, weight: .semibold)
}

extension View {
    /// Small uppercase section label (13pt semibold, +6% tracking).
    func sectionLabelStyle(_ color: Color = Theme.textSecondary) -> some View {
        font(Theme.sectionLabel).textCase(.uppercase).tracking(13 * 0.06).foregroundStyle(color)
    }
}
```

```swift
// Design/Glass.swift
import SwiftUI

extension View {
    /// Card: fill white 8%, 1pt white 15% border (not live glass — cheap in long lists).
    func cardGlass(radius: CGFloat) -> some View {
        background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }
    /// Control: interactive Liquid Glass.
    func controlGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        glassEffect(tint.map { Glass.regular.tint($0).interactive() } ?? .regular.interactive(), in: shape)
    }
    /// Floating panel over video.
    func panelGlass(radius: CGFloat) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
```

```swift
// Design/PressableButtonStyle.swift
import SwiftUI

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : Theme.spring, value: configuration.isPressed)
    }
}
```

- [ ] **Step 2: Implement environment, route, poster, toast, pill**

```swift
// App/Route.swift
import Foundation
enum Route: Hashable { case folder(UUID), unsorted, favorites }
```

```swift
// App/AppEnvironment.swift
import SwiftUI
import SwiftData
import RepasoCore

struct ToastState: Identifiable {
    let id = UUID()
    let text: String
    let undo: (() -> Void)?
}

@Observable @MainActor
final class AppEnvironment {
    let videos: VideoStore
    let thumbnails: ThumbnailStore
    var toast: ToastState?
    private var toastTask: Task<Void, Never>?

    init() throws {
        videos = try VideoStore.appDefault()
        thumbnails = try ThumbnailStore.appDefault(videos: videos)
    }

    func library(_ ctx: ModelContext) -> LibraryService {
        let videos = videos, thumbnails = thumbnails
        return LibraryService(context: ctx) { files, ids in
            files.forEach(videos.remove(fileName:))
            Task { await thumbnails.remove(ids: ids) }
        }
    }

    func showToast(_ text: String, undo: (() -> Void)? = nil, seconds: Double = 3.8) {
        toast = ToastState(text: text, undo: undo)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    /// Runs `body`; on failure shows "Couldn't save".
    func perform(_ body: () throws -> Void) {
        do { try body() } catch { showToast("Couldn't save", seconds: 2.2) }
    }

    func sweepOrphans(_ ctx: ModelContext) {
        let referenced = Set(((try? ctx.fetch(FetchDescriptor<Original>())) ?? []).map(\.fileName))
        let videos = videos
        Task.detached(priority: .background) { videos.sweepOrphans(keeping: referenced) }
    }
}
```

```swift
// Components/PosterView.swift
import SwiftUI
import RepasoCore

struct PosterView: View {
    let request: ThumbnailRequest?
    var cornerRadius: CGFloat = Theme.Radius.thumb
    @Environment(AppEnvironment.self) private var env
    @State private var image: CGImage?

    var body: some View {
        Rectangle().fill(.white.opacity(0.06))
            .overlay {
                if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
                else { Image(systemName: "film").foregroundStyle(.white.opacity(0.3)) }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: request) {
                guard let request else { image = nil; return }
                image = await env.thumbnails.image(for: request)
            }
            .accessibilityHidden(true)
    }
}
```

```swift
// Components/Toast.swift
import SwiftUI

struct ToastView: View {
    let toast: ToastState
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            if let undo = toast.undo {
                Button("Undo") { undo(); dismiss() }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 18).frame(minHeight: 48)
        .glassEffect(.regular, in: Capsule())
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Hosts the app-wide toast above the bottom pill.
    func toastHost(_ env: AppEnvironment) -> some View {
        overlay(alignment: .bottom) {
            if let toast = env.toast {
                ToastView(toast: toast) { env.toast = nil }.padding(.bottom, 110)
            }
        }
        .animation(Theme.spring, value: env.toast?.id)
    }
}
```

```swift
// Components/FloatingPill.swift
import SwiftUI

struct FloatingPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 28).frame(height: 56)
                .background(Theme.primaryButton, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.bottom, 38)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg], startPoint: .top, endPoint: .bottom)
                .frame(height: 140).allowsHitTesting(false).ignoresSafeArea()
        }
    }
}
```

- [ ] **Step 3: Wire `RepasoApp`**

```swift
import SwiftUI
import SwiftData
import RepasoCore

@main
struct RepasoApp: App {
    private let container: ModelContainer
    @State private var env: AppEnvironment

    init() {
        do {
            container = try RepasoSchema.makeContainer(inMemory: ProcessInfo.processInfo.arguments.contains("-uiTesting"))
            _env = State(initialValue: try AppEnvironment())
        } catch {
            fatalError("Repaso storage unavailable: \(error)")   // unrecoverable: no writable sandbox
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(env)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { env.sweepOrphans(container.mainContext) }
        }
        .modelContainer(container)
    }
}
```

`HomeView` is created in Task 8; for this task add a temporary `struct HomeView: View { var body: some View { Theme.bg.ignoresSafeArea() } }` in `Home/HomeView.swift` so the app builds.

- [ ] **Step 4: Build** — `xcodegen generate && xcodebuild build -project Repaso.xcodeproj -scheme Repaso -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`. Expected: success, no warnings from `Repaso/`.
- [ ] **Step 5: Checkpoint.**

---

### Task 8: Home screen + import pipeline UI

**Files:**
- Create: `Repaso/Components/FolderCard.swift`, `Repaso/Import/VideoTransfer.swift`, `Repaso/Import/ImportCoordinator.swift`, `Repaso/Import/ImportSheet.swift`
- Modify: `Repaso/Home/HomeView.swift`

**Interfaces:**
- Consumes: `FolderContents.rootFolders/unsortedOriginals/favorites/totals/clipCount/mosaic`, `LibraryService.createFolder/renameFolder/reorderFolder`, `VideoMetadata.load`, `VideoStore.adopt`.
- Produces:
  - `struct VideoTransfer: Transferable { let url: URL }` (FileRepresentation `.movie`, copies into `FileManager.temporaryDirectory`)
  - `@Observable @MainActor final class ImportCoordinator { struct Item: Identifiable { id, name, state: State, poster: ThumbnailRequest?, duration: Double?, size: Int64? }; enum State { waiting, copying(Double), done, failed(String) }; var items: [Item]; var isRunning: Bool; var overallProgress: Double; func start(_ picks: [PhotosPickerItem], into folder: Folder?, context: ModelContext, env: AppEnvironment); func retry(_ id: UUID) }` — one instance in `AppEnvironment` (`env.importer`)
  - `FolderCard(folder: Folder, isEditingName: Binding<Bool>)`
  - `ImportSheet()` reading `env.importer`

- [ ] **Step 1: `VideoTransfer`**

```swift
import CoreTransferable
import UniformTypeIdentifiers
import Foundation

struct VideoTransfer: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoTransfer(url: dest)
        }
    }
}
```

- [ ] **Step 2: `ImportCoordinator`** — sequential processing per spec §6:

```swift
import SwiftUI
import PhotosUI
import SwiftData
import RepasoCore

@Observable @MainActor
final class ImportCoordinator {
    struct Item: Identifiable {
        enum State: Equatable { case waiting, copying(Double), done, failed(String) }
        let id = UUID()
        let pick: PhotosPickerItem
        var name: String
        var state: State = .waiting
        var poster: ThumbnailRequest?
        var duration: Double?
        var size: Int64?
    }

    private(set) var items: [Item] = []
    private var target: Folder?
    private var runner: Task<Void, Never>?

    var isRunning: Bool { runner != nil }
    var overallProgress: Double {
        guard !items.isEmpty else { return 0 }
        let sum = items.reduce(0.0) { acc, item in
            switch item.state { case .done, .failed: acc + 1; case .copying(let p): acc + p; case .waiting: acc }
        }
        return sum / Double(items.count)
    }

    func start(_ picks: [PhotosPickerItem], into folder: Folder?, context: ModelContext, env: AppEnvironment) {
        guard !picks.isEmpty else { return }
        if !isRunning { items.removeAll() }
        target = folder
        items += picks.enumerated().map { Item(pick: $1, name: "Video \(items.count + $0 + 1)") }
        guard runner == nil else { return }
        runner = Task { [weak self] in
            await self?.drain(context: context, env: env)
            self?.runner = nil
        }
    }

    func retry(_ id: UUID, context: ModelContext, env: AppEnvironment) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].state = .waiting
        if runner == nil {
            runner = Task { [weak self] in await self?.drain(context: context, env: env); self?.runner = nil }
        }
    }

    private func drain(context: ModelContext, env: AppEnvironment) async {
        while let i = items.firstIndex(where: { $0.state == .waiting }) {
            await process(at: i, context: context, env: env)
        }
    }

    private func process(at i: Int, context: ModelContext, env: AppEnvironment) async {
        let id = items[i].id
        func update(_ change: (inout Item) -> Void) {
            if let j = items.firstIndex(where: { $0.id == id }) { change(&items[j]) }
        }
        update { $0.state = .copying(0.05) }
        do {
            guard let transfer = try await items[i].pick.loadTransferable(type: VideoTransfer.self) else {
                throw ImportError.unreadable
            }
            update { $0.state = .copying(0.7) }
            let meta = try await VideoMetadata.load(transfer.url)
            let fileName = try env.videos.adopt(fileAt: transfer.url)
            let original = try env.library(context).addOriginal(
                title: Self.title(recordedAt: meta.recordedAt, fallback: "Imported video"),
                fileName: fileName, duration: meta.duration, recordedAt: meta.recordedAt, to: target)
            update {
                $0.name = original.title; $0.duration = meta.duration
                $0.size = env.videos.fileSize(fileName); $0.poster = original.thumbnailRequest
                $0.state = .done
            }
            _ = await env.thumbnails.image(for: original.thumbnailRequest)
        } catch {
            update { $0.state = .failed(Self.message(for: error)) }
        }
    }

    /// Photos hands us UUID-like temp names, so titles come from the recording date.
    static func title(recordedAt: Date?, fallback: String) -> String {
        guard let recordedAt else { return fallback }
        return recordedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + " class"
    }

    static func message(for error: Error) -> String {
        if (error as NSError).code == NSFileWriteOutOfSpaceError { return "Not enough space" }
        return "Couldn't import this video"
    }

    enum ImportError: Error { case unreadable }
}
```

Add `let importer = ImportCoordinator()` to `AppEnvironment`.

- [ ] **Step 3: `ImportSheet`** — layout per spec §6 item 3: header `Importing N videos` + `NN%` (mono); `List`-free `ScrollView` of rows (46×32 `PosterView`, name 15 semibold, `TimeFormat.duration` + `ByteCountFormatter` size in 12pt secondary, trailing 28pt ring: `Circle().trim(from: 0, to: p).stroke(Theme.accent, lineWidth: 3)` → `Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)` with `.symbolEffect(.bounce, value: done)`; failed → rose `arrow.clockwise` button labelled "Retry import"). Bottom white pill `Hide` while `isRunning`, `Done` after. `.presentationDetents([.medium, .large])`, `.presentationBackground { Color(red: 48/255, green: 48/255, blue: 54/255).opacity(0.74).background(.ultraThinMaterial) }`, `.presentationCornerRadius(38)`.

- [ ] **Step 4: `FolderCard`** — 2×2 mosaic of `PosterView(request:cornerRadius: 0)` from `FolderContents.mosaic(for:)` in a 112pt-tall grid with 2pt gaps, clipped to radius 17; empty → `RoundedRectangle(17).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))` white 25%; name 15 semibold, count `"\(n) clips"` 13pt secondary; whole card `cardGlass(radius: 24)`, padding 10. Inline name editing: when `isEditingName`, show `TextField` with `@FocusState` focused on appear; on submit call `renameFolder`.

- [ ] **Step 5: `HomeView`**

Structure (exact copy and sizes from spec §7.1):

```swift
import SwiftUI
import SwiftData
import PhotosUI
import RepasoCore

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(AppEnvironment.self) private var env
    @Query(filter: #Predicate<Folder> { $0.parent == nil }, sort: \Folder.sortIndex) private var folders: [Folder]
    @Query(filter: #Predicate<Original> { $0.folder == nil }) private var unsorted: [Original]
    @Query(filter: #Predicate<Clip> { $0.isFavorite }) private var favorites: [Clip]
    @Query private var allClips: [Clip]
    @State private var path: [Route] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var showPicker = false
    @State private var showImport = false
    @State private var editingFolderID: UUID?
    @State private var deletingFolder: Folder?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if folders.isEmpty && unsorted.isEmpty { emptyState } else {
                        pinnedTiles
                        Text("Folders").sectionLabelStyle()
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(folders) { folder in
                                NavigationLink(value: Route.folder(folder.id)) {
                                    FolderCard(folder: folder, isEditingName: editingBinding(folder))
                                }
                                .buttonStyle(PressableButtonStyle())
                                .contextMenu { folderMenu(folder) }
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 140)
            }
            .background(Theme.bg.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                FloatingPill(title: "Import videos", systemImage: "square.and.arrow.down") { showPicker = true }
            }
            .photosPicker(isPresented: $showPicker, selection: $picks, matching: .videos, preferredItemEncoding: .current)
            .onChange(of: picks) { _, new in
                guard !new.isEmpty else { return }
                env.importer.start(new, into: nil, context: ctx, env: env)
                picks = []; showImport = true
            }
            .sheet(isPresented: $showImport) { ImportSheet() }
            .sheet(item: $deletingFolder) { DeleteFolderSheet(folder: $0) }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .folder(let id): FolderView(folderID: id, path: $path)
                case .unsorted: FolderView(folderID: nil, path: $path)
                case .favorites: FavoritesView(path: $path)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toastHost(env)
        }
    }
    // header: Text("Repaso") 40pt bold tracking -1.2; subtitle "\(allClips.count) clips in \(folders.count) folders";
    //   trailing 44pt round glass button "folder.badge.plus" (label "New folder") →
    //   withAnimation(Theme.spring) { let f = try lib.createFolder(named: "", in: nil); editingFolderID = f.id }
    // pinnedTiles: 2-column; Unsorted tile only if !unsorted.isEmpty (tray icon, green 8pt dot, "\(unsorted.count) new");
    //   Favorites tile (rose star.fill, "\(favorites.count) clips"); each NavigationLink(value:) with controlGlass(in: RoundedRectangle(22))
    // folderMenu: Rename (sets editingFolderID), Move up / Move down (reorderFolder by ∓1), Delete (role: .destructive → deletingFolder; empty folder deletes directly)
    // emptyState: cardGlass card with "film.stack" 40pt, "Import your first class video" 20 bold, one-line hint 15 secondary
}
```

The commented helper views are implemented in the same file as `private var header: some View`, `private var pinnedTiles`, `private func folderMenu(_:)`, `private var emptyState`, and `private func editingBinding(_:) -> Binding<Bool>` (true when `editingFolderID == folder.id`, setting false clears it). Mutations wrap in `env.perform { try env.library(ctx).… }`.

`FavoritesView` (same file as `FolderView`, Task 9) lists `FolderContents.favorites` as clip rows.

- [ ] **Step 6: Build** — Expected success. Temporarily stub `FolderView`, `FavoritesView`, `DeleteFolderSheet` with `Text` bodies if Task 9/10 haven't landed.
- [ ] **Step 7: Run in simulator** — `xcrun simctl boot "iPhone 17"; xcrun simctl install booted <app>; xcrun simctl launch booted com.amudgal.repaso`; add a sample video with `xcrun simctl addmedia booted <test.mov>`; import it; screenshot with the iOS Simulator control tool. Expected: Unsorted tile appears with "1 new", import sheet ring → check.
- [ ] **Step 8: Checkpoint.**

---

### Task 9: Folder screen, clip rows, original cards

**Files:**
- Create: `Repaso/Components/ClipRow.swift`, `Repaso/Components/OriginalCard.swift`, `Repaso/Folder/FolderView.swift`, `Repaso/Folder/FolderToolbar.swift`

**Interfaces:**
- Consumes: `FolderContents.*`, `ClipSort`, `LibraryService` toggles/moves/deletes.
- Produces:
  - `FolderView(folderID: UUID?, path: Binding<[Route]>)` (nil = Unsorted), `FavoritesView(path:)`
  - `ClipRow(clip: Clip, context: ClipRow.Context, onPlay: () -> Void, onMove: () -> Void, onInfo: () -> Void, onDelete: () -> Void)` with `enum Context { case underOriginal, loose }`
  - `OriginalCard(original: Original, clips: [Clip], onCut: () -> Void, rowActions: ...)`
  - `struct PlayerRequest: Identifiable { let id = UUID(); let queue: [Clip]; let index: Int; let title: String }` (defined here, consumed by Task 11)

- [ ] **Step 1: `ClipRow`** — 60pt row: `PosterView(clip.thumbnailRequest)` 46×32 radius 8; VStack name (15 semibold) + HStack `TimeFormat.duration(clip.length)` (mono 12) + tag `In \(folder.name)` (green text on `accentTint` capsule, 11pt semibold) when `context == .underOriginal && clip.isFiledElsewhere`, or `from \(original.title)` (12 secondary) when `.loose`; trailing three 44×44 buttons: star (`star.fill` rose / `star` white 72%, `.symbolEffect(.bounce, value: clip.isFavorite)`, label "Add to favorites"/"Remove from favorites"), learned (28pt circle; on = `Theme.accent` fill + black `checkmark`, off = white 30% stroke; label "Mark as learned"/"Mark as not learned"), play (36pt white 15% circle `play.fill`, label "Play clip"). `.swipeActions` are List-only, so rows use `.contextMenu` (Info, Move, Favorite, Learned, Delete) — no swipe in A (documented deviation: rows live in a `ScrollView`, not a `List`, to match the card design).
- [ ] **Step 2: `OriginalCard`** — `cardGlass(radius: 22)`; header: 64×44 poster with duration badge (black 55% capsule, mono 10), title 15 semibold, meta `"\(clips.count) clips"`, green **Cut** pill (`scissors`, `accentTint` bg, accent text, 36pt height, label "Cut clips from this video"), chevron toggling expansion with `.rotationEffect`. Expanded: divider + `ClipRow`s. Context menu on header: Move video, Delete video.
- [ ] **Step 3: `FolderToolbar`** — breadcrumb back button `‹ <parent name or Home>` (44pt height), `Menu` chip "Sort" with `ClipSort.allCases` and checkmark on active, toggle chip "Hide learned" (accent fill + onAccent text when on). Persist with `@AppStorage("sort.\(folderKey)")` and `@AppStorage("hideLearned.\(folderKey)")` where `folderKey = folderID?.uuidString ?? "unsorted"`.
- [ ] **Step 4: `FolderView`** — resolve folder by `@Query(filter: #Predicate<Folder> { $0.id == folderID })` (init-built predicate); sections in order: title 34 bold + summary `"\(n) clips · \(o) originals · \(k) folders"`; toolbar chips; **Folders** 3-column cards (`FolderCard` compact variant: 80pt mosaic) + a dashed `+` card (label "New subfolder"); **Originals** `OriginalCard`s; **Loose clips** `ClipRow(context: .loose)`; floating **Import** pill (imports into this folder via `env.importer.start(..., into: folder, ...)`). Rows rise 14pt + fade staggered 45ms on first appear (`.transition(.offset(y: 14).combined(with: .opacity))` with `.animation(Theme.spring.delay(Double(i) * 0.045))`, disabled when Reduce Motion). Presents: `MoveSheet`, `ClipInfoSheet`, `DeleteOriginalSheet`, `DeleteFolderSheet` (Task 10), `PlayerView` (Task 11) via `.fullScreenCover(item: $playerRequest)`, `CutView` (Task 12) via `.fullScreenCover(item: $cutOriginal)`.
  - Play queue: `FolderContents.playQueue(originals:loose:sort:hideLearned:)`; index = position of tapped clip.
  - Unsorted mode (`folderID == nil`): title "Unsorted", originals from `FolderContents.unsortedOriginals`, no subfolders, no loose clips.
- [ ] **Step 5: `FavoritesView`** — title "Favorites", sort chip only, list of `ClipRow(context: .loose)`; play queue = that list.
- [ ] **Step 6: Build + simulator check** — create folder, import into it, verify sections render; screenshot.
- [ ] **Step 7: Checkpoint.**

---

### Task 10: Sheets — Move, Clip info, Delete original, Delete folder

**Files:**
- Create: `Repaso/Sheets/SheetChrome.swift`, `Repaso/Sheets/MoveSheet.swift`, `Repaso/Sheets/ClipInfoSheet.swift`, `Repaso/Sheets/DeleteOriginalSheet.swift`, `Repaso/Sheets/DeleteFolderSheet.swift`

**Interfaces:**
- Consumes: `LibraryService.moveClip/moveOriginal/moveFolder/updateInfo/deleteOriginal/deleteFolder`, `LibraryError.invalidMoveTarget`, `FolderContents.rootFolders/subfolders`.
- Produces:
  - `enum MoveSubject: Identifiable { case clip(Clip), original(Original), folder(Folder) }`
  - `MoveSheet(subject: MoveSubject)`, `ClipInfoSheet(clip: Clip)`, `DeleteOriginalSheet(original: Original)`, `DeleteFolderSheet(folder: Folder)`
  - `View.repasoSheet()` (detents `.medium/.large`, Sheet material background, radius 38)

- [ ] **Step 1: `SheetChrome`**

```swift
import SwiftUI

extension View {
    func repasoSheet(detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        presentationDetents(detents)
            .presentationCornerRadius(Theme.Radius.sheet)
            .presentationBackground {
                Color(red: 48/255, green: 48/255, blue: 54/255).opacity(0.74).background(.ultraThinMaterial)
            }
            .presentationDragIndicator(.visible)
    }
}

struct PrimarySheetButton: View {
    let title: String
    var role: ButtonRole? = nil
    let action: () -> Void
    var body: some View {
        Button(role: role, action: action) {
            Text(title).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(role == .destructive ? .white : Theme.onAccent)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(role == .destructive ? Theme.rose : Theme.primaryButton, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
```

- [ ] **Step 2: `MoveSheet`** — title per subject ("Move clip" / "Move video" / "Move folder"); tree rows built recursively from `FolderContents.rootFolders` → `subfolders`, indent `22 * depth`, chevron to expand (all expanded to depth 1 initially), root row label: clip → "With its video", original → "Unsorted", folder → "Home". Disabled rows: current location (trailing "Current" 13pt secondary); for folder subject, the folder itself and its descendants. Selected row: `folder.fill` in accent + trailing `checkmark`. Button `Move to <Name>` (disabled until selection). On move: call the matching `LibraryService` method inside `env.perform`, switch to success state (`checkmark.circle.fill` 64pt accent with `.symbolEffect(.bounce)`, `Moved to <Name>`, and for clips `Still listed under its video.`), then after 1.2s dismiss and `env.showToast("Moved to <Name>", undo:)` where undo moves the subject back to its previous location.
- [ ] **Step 3: `ClipInfoSheet`** — Name `TextField`, Note `TextField(axis: .vertical)` with live counter `"\(note.count)/140"` (rose when at limit) and input truncated with `.onChange { if $1.count > 140 { note = String($1.prefix(140)) } }`; **Save** → `updateInfo`, shows `Saved` + check for 0.6s, dismiss. Detent `.medium`.
- [ ] **Step 4: `DeleteOriginalSheet`** — rose trash in 64pt `roseTint` circle; `Delete “<title>”?` 22 bold; `Its N clips will be deleted too.` (or `It has no clips.`); up to 4 clip names with posters; rose `PrimarySheetButton("Delete video and N clips", role: .destructive)` (or "Delete video"); Cancel text button. Calls `deleteOriginal`.
- [ ] **Step 5: `DeleteFolderSheet`** — `Delete “<name>”?`; if folder has no children/originals/loose clips: single rose "Delete folder". Otherwise rose "Delete contents" + white "Move contents up" + Cancel. Calls `deleteFolder(mode:)`. Pops navigation if the deleted folder is on the path (FolderView observes its folder disappearing and calls `dismiss()`).
- [ ] **Step 6: Build + simulator check** — move a clip to another folder: verify `In <Folder>` tag under original and loose row in target; Undo restores. Delete an original: its clips vanish everywhere.
- [ ] **Step 7: Checkpoint.**

---

### Task 11: Player

**Files:**
- Create: `Repaso/Player/PlayerLayerView.swift`, `Repaso/Player/PlayerModel.swift`, `Repaso/Player/SpeedControl.swift`, `Repaso/Player/PlayerView.swift`

**Interfaces:**
- Consumes: `PlayerRequest` (Task 9), `LoopController`, `VideoStore.url(for:)`, `LibraryService.toggleFavorite/toggleLearned/markPlayed`, `TimeFormat`.
- Produces: `PlayerView(request: PlayerRequest)`; `@Observable @MainActor final class PlayerModel { let player: AVPlayer; var isPlaying; var progress: Double; var loop: LoopController; var restingUntil: Date?; var speed: Double; var missingFile: Bool; func load(_ clip: Clip, videos: VideoStore); func togglePlay(); func setSpeed(_:); func toggleLoop(); func cycleGap(); func tearDown() }`

- [ ] **Step 1: `PlayerLayerView`**

```swift
import SwiftUI
import AVFoundation

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> LayerView {
        let v = LayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.backgroundColor = .black
        return v
    }
    func updateUIView(_ uiView: LayerView, context: Context) { uiView.playerLayer.player = player }
    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
```

- [ ] **Step 2: `PlayerModel`**

```swift
import AVFoundation
import Observation
import RepasoCore

@Observable @MainActor
final class PlayerModel {
    let player = AVPlayer()
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private(set) var restingUntil: Date?
    private(set) var missingFile = false
    var loop = LoopController()
    var speed: Double = 1 { didSet { if isPlaying { player.rate = Float(speed) } } }

    private var range: ClosedRange<Double> = 0...1
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var restTask: Task<Void, Never>?

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
    }

    func load(_ clip: Clip, videos: VideoStore) {
        restTask?.cancel(); restingUntil = nil
        guard let original = clip.original else { missingFile = true; return }
        let url = videos.url(for: original.fileName)
        missingFile = !FileManager.default.fileExists(atPath: url.path)
        guard !missingFile else { player.replaceCurrentItem(with: nil); return }
        range = clip.start...clip.end
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        item.forwardPlaybackEndTime = CMTime(seconds: clip.end, preferredTimescale: 600)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reachedEnd() }
        }
        player.replaceCurrentItem(with: item)
        seekToStart { [weak self] in self?.play() }
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        restTask?.cancel(); restingUntil = nil
        if progress >= 0.999 { seekToStart { [weak self] in self?.player.playImmediately(atRate: Float(self?.speed ?? 1)) } }
        else { player.playImmediately(atRate: Float(speed)) }
        isPlaying = true
    }

    func pause() {
        restTask?.cancel(); restingUntil = nil
        player.pause()
        isPlaying = false
    }

    func toggleLoop() { loop.loopEnabled.toggle() }
    func cycleGap() { loop.cycleGap() }

    func tearDown() {
        pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil; endObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    private func reachedEnd() {
        switch loop.actionAtEnd() {
        case .restart:
            seekToStart { [weak self] in guard let self else { return }; player.playImmediately(atRate: Float(speed)) }
        case .restartAfter(let seconds):
            player.pause()
            restingUntil = .now.addingTimeInterval(seconds)
            restTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard let self, !Task.isCancelled else { return }
                restingUntil = nil
                seekToStart { self.player.playImmediately(atRate: Float(self.speed)) }
            }
        case .stop:
            player.pause(); isPlaying = false; progress = 1
        }
    }

    private func seekToStart(then: @escaping @MainActor () -> Void) {
        player.seek(to: CMTime(seconds: range.lowerBound, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in then() }
        }
    }

    private func tick(_ t: Double) {
        let len = range.upperBound - range.lowerBound
        guard len > 0 else { return }
        progress = min(1, max(0, (t - range.lowerBound) / len))
    }
}
```

- [ ] **Step 3: `SpeedControl`** — 3-segment capsule (`controlGlass(in: Capsule())`, height 44), sliding accent pill behind the active label using `matchedGeometryEffect(id: "speedPill", in: ns)`; labels `0.5×`, `0.75×`, `1×` 16pt semibold `.monospacedDigit()`, active = `Theme.onAccent`, others `Theme.textPrimary`; `accessibilityElement(children: .contain)` and each segment labelled "Speed 0.5x" etc. with `.isSelected` trait.
- [ ] **Step 4: `PlayerView`** — layout per spec §7.3:
  - `ZStack`: `Color.black.ignoresSafeArea()`, `PlayerLayerView(player: model.player).ignoresSafeArea()` with `.contentShape(Rectangle()).onTapGesture { model.togglePlay(); flash += 1; wake() }`.
  - Flash: centered 96pt glass circle with `play.fill`/`pause.fill`, animated via `.keyframeAnimator(initialValue:trigger: flash)` scale 0.6→1→1.35 and opacity 1→0 over 0.7s.
  - Gap ring: when `model.restingUntil != nil`, centered 72pt accent ring `Circle().trim` animating from 1→0 over the gap + "Again in Ns" 13pt.
  - Top bar: 44pt glass close button `chevron.down` (label "Close player"), centre capsule `"\(request.title) \(index + 1) / \(queue.count)"`.
  - Bottom panel (`panelGlass(radius: 32)`, `.padding(.horizontal, 12)`, padding 18/16/14, spacing 14): name 20 bold; source `"\(original.title) · \(recordedAt formatted .abbreviated)"` 13 secondary + duration mono; note 15 if present; progress `Capsule().frame(height: 3)` with white fill `.scaleEffect(x: model.progress, anchor: .leading)`; `SpeedControl($speed)` bound to `@AppStorage("playbackSpeed") var speed = 1.0` (assign to `model.speed` on change and on appear); row: Loop pill (`repeat`, accentTint/accent when on), Gap pill (`timer`, text `model.loop.gap.label`, opacity 0.4 when loop off), `Spacer()`, favorite 44pt (rose), learned 44pt (accent fill when on).
  - Idle chrome: `@State chromeVisible = true`; a `Task` restarted by `wake()` sleeps 2.4s then, if playing, sets `false`. Top bar `.opacity(chromeVisible ? 1 : 0).offset(y: chromeVisible ? 0 : -12).allowsHitTesting(chromeVisible)`; panel `.opacity(chromeVisible || !model.isPlaying ? 1 : 0.42)`. Any button action calls `wake()`; `.simultaneousGesture(TapGesture().onEnded { wake() })` on the panel.
  - Lifecycle: `.onAppear { UIApplication.shared.isIdleTimerDisabled = true; model.speed = speed; model.load(currentClip, videos: env.videos); env.perform { try lib.markPlayed(currentClip) } }`; `.onDisappear { UIApplication.shared.isIdleTimerDisabled = false; model.tearDown() }`.
  - Missing file: replace video with centred glass card "Video file missing" + rose button "Delete video" → `DeleteOriginalSheet`.
  - `.statusBarHidden()`, `.persistentSystemOverlays(.hidden)`.
- [ ] **Step 5: Build + simulator acceptance** — open a clip: it plays from its start, loops at its end; tap pauses instantly; 0.5× is slower with normal pitch (listen on device in Task 13); gap 1s shows ring; chrome dims after 2.4s.
- [ ] **Step 6: Checkpoint.**

---

### Task 12: Cut mode

**Files:**
- Create: `Repaso/Cut/CutModel.swift`, `Repaso/Cut/Filmstrip.swift`, `Repaso/Cut/ClipTray.swift`, `Repaso/Cut/CutView.swift`

**Interfaces:**
- Consumes: `CutSession`, `ClipRange`, `LibraryService.addClip/updateRange/updateInfo`, `FolderContents.clips(of:sort:hideLearned:)`, `PlayerLayerView`, `TimeFormat`.
- Produces: `CutView(original: Original)`; `@Observable @MainActor final class CutModel { let player: AVPlayer; var time: Double; var isPlaying: Bool; var session: CutSession; var selectedID: UUID?; var draftRange: ClosedRange<Double>?; var frozenWindowStart: Double?; var frames: [CGImage?]; func togglePlay(); func jump(_ delta: Double); func seek(_ t: Double); func windowStart(clips: [Clip]) -> Double; func loadFrames(windowStart: Double) async }`

- [ ] **Step 1: `CutModel`** — `AVPlayer` on the original (`audioTimePitchAlgorithm = .timeDomain`), periodic observer every 1/20s updates `time`, `seek` uses zero tolerance when paused and 0.1s tolerance while dragging (`seek(_:precise:)`); `windowStart(clips:)` = `frozenWindowStart ?? CutSession.windowStart(center: selected?.mid ?? time, duration:)`; `loadFrames` uses one `AVAssetImageGenerator` (maximumSize 120×120, tolerance 0.5s) to fetch 10 frames evenly across the window via `generator.images(for:)`, cached in a `[Int: [CGImage?]]` keyed by `Int(windowStart * 10)`.
- [ ] **Step 2: `Filmstrip`** — width from `GeometryReader`, height 56, radius 10. Layers: frame images in an `HStack(spacing: 0)`; translucent ranges for non-selected clips intersecting the window (`accent.opacity(0.22)` fill, 2pt `accent.opacity(0.6)` top/bottom borders); rose recording range from `session.markStart` to `time` (`rose.opacity(0.28)`, 3pt rose borders); selected clip outline (3pt accent top/bottom, `accent.opacity(0.10)` fill) with 16×56 accent handles (chevrons), hit area expanded to 44pt width; white 3pt playhead with glow. Gestures: `DragGesture(minimumDistance: 0)` on the strip → scrub (freeze window, pause, restore play state on end); on handles → `CutSession.trimStart/trimEnd` into `model.draftRange`, `seek(handle time)`, on end `env.perform { try lib.updateRange(clip, start:end:) }` and clear draft + unfreeze. Labels under strip: `TimeFormat.range(windowStart)` · hint (`Drag to scrub` / `Drag the handles to trim`) · `TimeFormat.range(windowStart + windowLength)` 12pt secondary. Handles: `.accessibilityElement()`, label "Clip start"/"Clip end", value `TimeFormat.precise`, `.accessibilityAdjustableAction { dir in ±0.1s via trim functions + updateRange }`.
- [ ] **Step 3: `ClipTray`** — horizontal `ScrollView` of 156pt cards (padding 10/12, radius 20, white 11% fill, 1.5pt border accent when selected else white 18%), newest first (`sort: .dateAdded`); name 15 semibold (selected + tapped → inline `TextField`, commit via `updateInfo(name:note: clip.note ?? "")`), range `"\(TimeFormat.range(a))–\(TimeFormat.range(b))"` mono 12, length `TimeFormat.length` (accent when selected). New card transition: `.transition(.offset(y: 40).combined(with: .scale(scale: 0.6)).combined(with: .opacity))` with `Theme.spring`. Tap: select + `seek(clip.start)`; tap selected (outside name): deselect. Header row: "Clips" section label + count.
- [ ] **Step 4: `CutView`** — `VStack(spacing: 0)`:
  1. Video area 430pt: `PlayerLayerView` with `UnevenRoundedRectangle(bottomLeadingRadius: 34, bottomTrailingRadius: 34)` clip, tap → `togglePlay`; overlay top bar: glass **Done** capsule (dismiss; cancels an in-progress mark) + centred title capsule; mark-flash overlay (accent or rose, opacity 0.35→0 over 0.5s, keyed by a counter).
  2. Time row: `"\(TimeFormat.precise(time)) / \(TimeFormat.precise(duration))"` mono 30 (secondary part 50% opacity), then `−5s` (label "Back 5 seconds"), 56pt white circle play/pause, `+5s` (label "Forward 5 seconds").
  3. Mark button: full width, height 60, Capsule, 18pt bold `Theme.onAccent`; idle accent "Mark start"; recording rose "Mark end" + pulsing 10pt dot + live `TimeFormat.length(session.liveLength(at: time)!)`; pulsing ring overlay (`.phaseAnimator`, off with Reduce Motion). Action: `if let r = session.mark(at: time) { let c = try lib.addClip(to: original, start: r.lowerBound, end: r.upperBound); selectedID = c.id; env.showToast("\(c.name) added", seconds: 2.2) } else { play() }`; `sensoryFeedback(.impact(weight: .medium), trigger: markCount)`.
  4. Filmstrip (horizontal padding 20).
  5. Clip tray.
  - Background `Theme.bg`; `.toastHost(env)`; `isIdleTimerDisabled` on while open.
- [ ] **Step 5: Build + simulator acceptance** — Mark start/end creates "Clip N" at the front of the tray and in the Folder screen; dragging a handle below 0.5s stops at 0.5s; scrubbing pauses and resumes.
- [ ] **Step 6: Checkpoint.**

---

### Task 13: UI smoke test, polish, accessibility, TestFlight readiness

**Files:**
- Modify: `RepasoUITests/SmokeTests.swift`, `Repaso/Resources/Assets.xcassets/AppIcon.appiconset/` (1024 icon)
- Create: `docs/TESTFLIGHT.md`

- [ ] **Step 1: Write the failing UI test**

```swift
import XCTest

final class SmokeTests: XCTestCase {
    func testCreateFolderFromEmptyState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Import your first class video"].waitForExistence(timeout: 5))
        app.buttons["New folder"].tap()
        let field = app.textFields["Folder name"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Turns\n")
        XCTAssertTrue(app.staticTexts["Turns"].waitForExistence(timeout: 2))
    }
}
```

Requires `FolderCard`'s inline `TextField` to have `.accessibilityLabel("Folder name")`, and Home to show the folder grid (not the empty state) once a folder exists.

- [ ] **Step 2: Run** — `xcodebuild test -project Repaso.xcodeproj -scheme Repaso -destination 'platform=iOS Simulator,name=iPhone 17'`. Expected: package tests + `SmokeTests` pass. Fix and re-run until green.
- [ ] **Step 3: Accessibility audit** — run Accessibility Inspector audit on Home, Folder, Player, Cut in the simulator; fix every "Hit area too small" and "Element has no description" in our views. Verify Reduce Motion (Settings → Accessibility → Motion) removes stagger/overshoot/pulses.
- [ ] **Step 4: Performance check** — seed 200 clips with a DEBUG-only launch argument `-seedLibrary` (in `RepasoApp`, `#if DEBUG`: creates 10 folders × 20 clips on one imported sample video); scroll Home/Folder in Instruments' SwiftUI template (or visually at 120Hz on device); no hitches > 1 frame on scroll after thumbnails are cached.
- [ ] **Step 5: Device acceptance (spec §2)** — on a physical iPhone: clip opens with no spinner; tap-to-pause immediate; 0.5× pitch unchanged; move keeps clip under original; delete original removes clips only.
- [ ] **Step 6: App icon + `docs/TESTFLIGHT.md`** — 1024×1024 icon (volt green `R` glyph on `#030303`); doc lists: set `DEVELOPMENT_TEAM` in `project.yml`, `xcodegen generate`, Product → Archive, upload via Organizer, add internal testers, export compliance = no non-exempt encryption (already in Info.plist).
- [ ] **Step 7: Final checkpoint** — `git status`, `git diff --stat`; report results. Commit only if the user asks.

---

## Self-review notes

- Spec coverage: §4 model/rules → Tasks 2–4; §5 storage → Task 6; §6 import → Tasks 6, 8; §7.1 → Task 8; §7.2 → Task 9; §7.3 → Tasks 5, 11; §7.4 → Tasks 5, 12; §7.5 → Tasks 8, 10; §8 motion → Tasks 7–12; §9 errors → Tasks 3 (save rollback), 6 (missing video), 8 (import failures), 11 (missing file); §10 testing → every task + Task 13; §11 prerequisites → Task 0.
- Deviation recorded: clip rows use context menus instead of swipe actions (ScrollView cards, not `List`). Folder reorder uses Move up/down menu items in A; drag reorder is B.
