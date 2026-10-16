# Repaso Sub-project B (Drag and drop, Share, Photos clean-up, Tags) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add drag-to-reorder on Home, drag-a-clip-onto-a-folder with spring-loading and Undo, clip share export, delete-from-Photos after import, and instructor/event tags with autocomplete.

**Architecture:** Rules and numbers go into `RepasoCore` (`LibraryService` additions plus pure helpers and `ClipExporter`), tested with Swift Testing. The app uses system drag and drop (`draggable` / `dropDestination`) with a shared `DragState` that knows when a drag starts and ends (iOS 27 session callback, iOS 26 hover-count fallback).

**Tech Stack:** SwiftUI (iOS 26+, built with Xcode 27), SwiftData, AVFoundation (`AVAssetExportSession`), Photos (`PHAssetChangeRequest`), Swift Testing, XCUITest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-16-repaso-drag-share-tags-design.md`

## Global Constraints

- Deployment target iOS 26.0; Swift 6 with `SWIFT_STRICT_CONCURRENCY: complete`; zero build warnings.
- Prefix every tool command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Destination: `platform=iOS Simulator,name=iPhone 18 Pro`. If the simulator says "runtime not available", run `killall -9 com.apple.CoreSimulator.CoreSimulatorService`.
- Every library mutation goes through `LibraryService`; views call it through `env.perform { try env.library(ctx)... }`.
- Touch targets ≥ 44×44pt; every icon-only button has an `accessibilityLabel`.
- Motion values: jiggle ±0.8° per 0.32s; hover scale 1.08 + lift 4pt; ring fill 0.9s; absorb 1.1 → 0.92 → 1.04 → 1 over 0.6s; toast with Undo 3.8s; lift 1.07/−3° (folder), 1.04/−2.5° (clip). Reduce Motion drops jiggle, overshoot and lift transforms.
- No commits unless the user asks (user rule overrides the "Commit" steps: skip them).

## Review Focus

1. A drag cancelled by releasing over blank space must leave no stuck "drag mode" (jiggle, green labels). → Task 4/5 manual check plus the `DragState` fallback test in Task 4.
2. Dropping a clip on the folder it already lives in must not move it or show a toast. → `dropClipIsNoOpOnItsOwnFolder` test (Task 1).
3. Undo after the previous folder was deleted must not crash or resurrect it. → `undoAfterPreviousFolderDeletedFilesWithVideo` test (Task 1).
4. Tags typed with stray commas, spaces or duplicate case ("marco, Marco ,") must save one clean name. → `TagText` tests (Task 2).
5. Clip names with `/` or `:` must still export to a valid file. → `ClipExport.fileName` tests (Task 3).

---

### Task 1: LibraryService — folder order, clip drop + undo, tags

**Files:**
- Modify: `Packages/RepasoCore/Sources/RepasoCore/Library/LibraryService.swift`
- Modify: `Packages/RepasoCore/Sources/RepasoCore/Model/Clip.swift` (add `effectiveFolder`)
- Create: `Packages/RepasoCore/Sources/RepasoCore/Library/ClipMoveReceipt.swift`
- Create: `Packages/RepasoCore/Tests/RepasoCoreTests/DragLibraryTests.swift`

**Interfaces:**
- Produces: `setFolderOrder(_ ordered: [Folder]) throws`, `dropClip(_:on:) throws -> ClipMoveReceipt?`, `undo(_ receipt: ClipMoveReceipt) throws`, `setTags(_:instructors:event:) throws`, `addOriginal(title:fileName:duration:recordedAt:to:instructors:event:)`, `Clip.effectiveFolder: Folder?`.
- Consumes: `TagText.normalized(_:)` from Task 2 (implement Task 2's `TagText` first or together).

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import RepasoCore

@MainActor
struct DragLibraryTests {
    let ctx: ModelContext
    let lib: LibraryService

    init() throws {
        ctx = try makeContext()
        lib = LibraryService(context: ctx)
    }

    func original(in folder: Folder?) throws -> Original {
        try lib.addOriginal(title: "Class", fileName: "c.mov", duration: 120, recordedAt: nil, to: folder)
    }

    @Test func setFolderOrderPersistsPositions() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: nil)
        let c = try lib.createFolder(named: "C", in: nil)
        try lib.setFolderOrder([a, c, b])
        #expect([a.sortIndex, c.sortIndex, b.sortIndex] == [0, 1, 2])
    }

    @Test func setFolderOrderRejectsMixedParents() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: a)
        #expect(throws: LibraryError.invalidMoveTarget) { try lib.setFolderOrder([a, b]) }
    }

    @Test func dropClipFilesItAndUndoRestoresWithItsVideo() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let hammer = try lib.createFolder(named: "Hammerlock", in: turns)
        let clip = try lib.addClip(to: try original(in: turns), start: 1, end: 4)
        let receipt = try #require(try lib.dropClip(clip, on: hammer))
        #expect(clip.folder?.id == hammer.id)
        #expect(receipt.previousFolder == nil)
        try lib.undo(receipt)
        #expect(clip.folder == nil)
    }

    @Test func undoRestoresAPreviousFolder() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: nil)
        let clip = try lib.addClip(to: try original(in: nil), start: 1, end: 4)
        try lib.moveClip(clip, to: a)
        let receipt = try #require(try lib.dropClip(clip, on: b))
        try lib.undo(receipt)
        #expect(clip.folder?.id == a.id)
    }

    @Test func dropClipIsNoOpOnItsOwnFolder() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let clip = try lib.addClip(to: try original(in: turns), start: 1, end: 4)
        #expect(try lib.dropClip(clip, on: turns) == nil)
        #expect(clip.folder == nil)
    }

    @Test func dropOnOriginalsFolderBringsClipBackWithItsVideo() throws {
        let turns = try lib.createFolder(named: "Turns", in: nil)
        let other = try lib.createFolder(named: "Other", in: nil)
        let clip = try lib.addClip(to: try original(in: turns), start: 1, end: 4)
        try lib.moveClip(clip, to: other)
        _ = try lib.dropClip(clip, on: turns)
        #expect(clip.folder == nil)
        #expect(clip.effectiveFolder?.id == turns.id)
    }

    @Test func undoAfterPreviousFolderDeletedFilesWithVideo() throws {
        let a = try lib.createFolder(named: "A", in: nil)
        let b = try lib.createFolder(named: "B", in: nil)
        let clip = try lib.addClip(to: try original(in: nil), start: 1, end: 4)
        try lib.moveClip(clip, to: a)
        let receipt = try #require(try lib.dropClip(clip, on: b))
        try lib.deleteFolder(a, mode: .deleteContents)
        try lib.undo(receipt)
        #expect(clip.folder == nil)
    }

    @Test func setTagsNormalises() throws {
        let o = try original(in: nil)
        try lib.setTags([o], instructors: [" Marco ", "marco", "", "Sara"], event: "  ")
        #expect(o.instructors == ["Marco", "Sara"])
        #expect(o.event == nil)
        try lib.setTags([o], instructors: [], event: " Berlin 2026 ")
        #expect(o.event == "Berlin 2026")
    }

    @Test func addOriginalStoresTags() throws {
        let o = try lib.addOriginal(title: "T", fileName: "t.mov", duration: 10, recordedAt: nil, to: nil,
                                    instructors: ["Ataca & Alemana"], event: "Berlin 2026")
        #expect(o.instructors == ["Ataca & Alemana"])
        #expect(o.event == "Berlin 2026")
    }
}
```

- [ ] **Step 2: Run to verify they fail** — `DEVELOPER_DIR=… xcodebuild test -project Repaso.xcodeproj -scheme Repaso -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:RepasoCoreTests` → compile errors (`setFolderOrder` missing).

- [ ] **Step 3: Implement**

`ClipMoveReceipt.swift`:

```swift
/// What a drag-drop changed, so the toast's Undo can put it back.
@MainActor
public struct ClipMoveReceipt {
    public let clip: Clip
    /// nil = the clip lived with its video.
    public let previousFolder: Folder?
    public let destination: Folder
}
```

`Clip.swift` addition:

```swift
/// Where the clip shows up as filed: its own folder, or its original's when it lives with its video.
public var effectiveFolder: Folder? { folder ?? original?.folder }
```

`LibraryService.swift` additions (Folders, Originals and Clips MARK sections):

```swift
/// Persists a full sibling order (end of a Home reorder drag).
public func setFolderOrder(_ ordered: [Folder]) throws {
    guard let parentID = ordered.first.map({ $0.parent?.id }) else { return }
    guard ordered.allSatisfy({ $0.parent?.id == parentID }) else { throw LibraryError.invalidMoveTarget }
    for (index, folder) in ordered.enumerated() { folder.sortIndex = index }
    try save()
}

public func setTags(_ originals: [Original], instructors: [String], event: String?) throws {
    let names = TagText.normalized(instructors)
    let cleanEvent = event.flatMap(Self.cleanName)
    for original in originals {
        original.instructors = names
        original.event = cleanEvent
    }
    try save()
}

/// Files a clip by drag. nil when it already lives in `folder`.
public func dropClip(_ clip: Clip, on folder: Folder) throws -> ClipMoveReceipt? {
    guard clip.effectiveFolder?.id != folder.id else { return nil }
    let receipt = ClipMoveReceipt(clip: clip, previousFolder: clip.folder, destination: folder)
    try moveClip(clip, to: folder)
    return receipt
}

/// Puts a dropped clip back; a since-deleted previous folder means "with its video".
public func undo(_ receipt: ClipMoveReceipt) throws {
    guard receipt.clip.modelContext != nil, !receipt.clip.isDeleted else { return }
    let previous = receipt.previousFolder.flatMap { $0.modelContext == nil || $0.isDeleted ? nil : $0 }
    try moveClip(receipt.clip, to: previous)
}
```

`addOriginal` gains `instructors: [String] = [], event: String? = nil` and sets `original.instructors = TagText.normalized(instructors)` and `original.event = event.flatMap(Self.cleanName)` before insert.

- [ ] **Step 4: Run tests** — all `DragLibraryTests` pass, the 44 A tests still pass.

---

### Task 2: Pure helpers — FolderOrder, TagText, TagSuggestions, PhotosCleanupText, ImportSummary

**Files:**
- Create: `Packages/RepasoCore/Sources/RepasoCore/Queries/FolderOrder.swift`
- Create: `Packages/RepasoCore/Sources/RepasoCore/Tags/TagText.swift`
- Create: `Packages/RepasoCore/Sources/RepasoCore/Tags/TagSuggestions.swift`
- Create: `Packages/RepasoCore/Sources/RepasoCore/Import/ImportText.swift` (`PhotosCleanupText`, `ImportSummary`)
- Create: `Packages/RepasoCore/Tests/RepasoCoreTests/TagTests.swift`, `HelperTests.swift`

**Interfaces:**
- Produces: `FolderOrder.moving(_:onto:in:) -> [UUID]`; `TagText.normalized(_:)`, `.instructors(from:)`, `.lastToken(of:)`, `.completing(_:with:)`; `TagSuggestions.instructors(for:excluding:in:limit:)`, `.events(for:excluding:in:limit:)`; `PhotosCleanupText.prompt(count:)`, `.detail`, `.removed`, `.kept`, `.failed`, `.needsAccess`; `ImportSummary.recordedLine(_:calendar:locale:) -> String?`.

- [ ] **Step 1: Write failing tests**

```swift
import Testing
import Foundation
import SwiftData
@testable import RepasoCore

struct HelperTests {
    let a = UUID(), b = UUID(), c = UUID()

    @Test func movingForwardLandsAfterTarget() {
        #expect(FolderOrder.moving(a, onto: c, in: [a, b, c]) == [b, c, a])
    }
    @Test func movingBackwardLandsBeforeTarget() {
        #expect(FolderOrder.moving(c, onto: a, in: [a, b, c]) == [c, a, b])
    }
    @Test func movingOntoItselfOrUnknownIsUnchanged() {
        #expect(FolderOrder.moving(a, onto: a, in: [a, b]) == [a, b])
        #expect(FolderOrder.moving(UUID(), onto: a, in: [a, b]) == [a, b])
    }
    @Test func photosPromptText() {
        #expect(PhotosCleanupText.prompt(count: 3) == "Delete 3 videos from Photos?")
        #expect(PhotosCleanupText.prompt(count: 1) == "Delete this video from Photos?")
    }
    @Test func recordedLine() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let oct12 = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10)))
        let oct9 = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 10)))
        #expect(ImportSummary.recordedLine([], calendar: cal, locale: locale) == nil)
        #expect(ImportSummary.recordedLine([oct12, oct12], calendar: cal, locale: locale) == "Recorded Oct 12, 2026")
        let span = try #require(ImportSummary.recordedLine([oct12, oct9], calendar: cal, locale: locale))
        #expect(span.hasPrefix("Recorded Oct 9"))
        #expect(span.hasSuffix("12, 2026"))
    }
}

@MainActor
struct TagTests {
    @Test func instructorsSplitTrimAndDedupe() {
        #expect(TagText.instructors(from: "marco, Marco ,, Sara ") == ["marco", "Sara"])
    }
    @Test func lastTokenAndCompletion() {
        #expect(TagText.lastToken(of: "Marco, At") == "At")
        #expect(TagText.completing("Marco, At", with: "Ataca & Alemana") == "Marco, Ataca & Alemana, ")
        #expect(TagText.completing("", with: "Sara") == "Sara, ")
    }
    @Test func suggestionsRankByUseThenRecency() throws {
        let ctx = try makeContext()
        let lib = LibraryService(context: ctx)
        let old = Date(timeIntervalSince1970: 0)
        let o1 = try lib.addOriginal(title: "1", fileName: "1", duration: 1, recordedAt: nil, to: nil, instructors: ["Marco & Sara"], event: "Berlin 2026")
        let o2 = try lib.addOriginal(title: "2", fileName: "2", duration: 1, recordedAt: nil, to: nil, instructors: ["Marco & Sara", "Studio team"], event: "Thursday class")
        let o3 = try lib.addOriginal(title: "3", fileName: "3", duration: 1, recordedAt: nil, to: nil, instructors: ["Ataca & Alemana"], event: "berlin 2026")
        o1.importedAt = old
        let all = [o1, o2, o3]
        #expect(TagSuggestions.instructors(for: "", in: all) == ["Marco & Sara", "Ataca & Alemana", "Studio team"])
        #expect(TagSuggestions.events(for: "", in: all).first?.lowercased() == "berlin 2026")
        #expect(TagSuggestions.events(for: "", in: all).count == 2)
    }
    @Test func suggestionsPreferPrefixThenSubstringAndExclude() throws {
        let ctx = try makeContext()
        let lib = LibraryService(context: ctx)
        let o = try lib.addOriginal(title: "1", fileName: "1", duration: 1, recordedAt: nil, to: nil,
                                    instructors: ["Sara Lee", "Ataca & Alemana", "Alex"], event: nil)
        #expect(TagSuggestions.instructors(for: "al", in: [o]) == ["Alex", "Ataca & Alemana"])
        #expect(TagSuggestions.instructors(for: "a", excluding: ["Alex"], in: [o], limit: 1) == ["Ataca & Alemana"])
        #expect(TagSuggestions.instructors(for: "alex", in: [o]).isEmpty)
        #expect(TagSuggestions.instructors(for: "ee", in: [o]) == ["Sara Lee"])
    }
}
```

(`"al"`: "Alex" and "Ataca & Alemana" are prefix matches — Alex on the value, Alemana on a word; ranks tie on use count and date, so alphabetical. "Sara Lee" has no word starting "al".)

- [ ] **Step 2: Run** → compile failures.

- [ ] **Step 3: Implement**

```swift
// FolderOrder.swift
import Foundation

public enum FolderOrder {
    /// Live reorder: `id` takes `target`'s position (lands after it moving forward, before it moving back).
    public static func moving(_ id: UUID, onto target: UUID, in ids: [UUID]) -> [UUID] {
        guard id != target, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else { return ids }
        var out = ids
        out.remove(at: from)
        out.insert(id, at: to)
        return out
    }
}
```

```swift
// TagText.swift
import Foundation

/// Parsing for the import sheet's tag fields.
public enum TagText {
    /// Trims, drops empties, de-duplicates case-insensitively (first spelling wins).
    public static func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    public static func instructors(from text: String) -> [String] {
        normalized(text.split(separator: ",").map(String.init))
    }

    /// The name being typed: everything after the last comma.
    public static func lastToken(of text: String) -> String {
        let last = text.split(separator: ",", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return last.trimmingCharacters(in: .whitespaces)
    }

    /// Replaces the name being typed with `suggestion` and readies the field for the next one.
    public static func completing(_ text: String, with suggestion: String) -> String {
        var parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.isEmpty { parts = [""] }
        parts[parts.count - 1] = suggestion
        return parts.filter { !$0.isEmpty }.joined(separator: ", ") + ", "
    }
}
```

```swift
// TagSuggestions.swift
import Foundation

/// Autocomplete chips for the import sheet, drawn from earlier imports.
@MainActor
public enum TagSuggestions {
    public static func instructors(for query: String, excluding: [String] = [], in originals: [Original], limit: Int = 3) -> [String] {
        rank(originals.flatMap { o in o.instructors.map { ($0, o.importedAt) } }, query: query, excluding: excluding, limit: limit)
    }

    public static func events(for query: String, excluding: [String] = [], in originals: [Original], limit: Int = 3) -> [String] {
        rank(originals.compactMap { o in o.event.map { ($0, o.importedAt) } }, query: query, excluding: excluding, limit: limit)
    }

    /// Most used first, then most recent, then alphabetical. A query keeps prefix matches (whole value or any word)
    /// ahead of other substring matches.
    static func rank(_ uses: [(String, Date)], query: String, excluding: [String], limit: Int) -> [String] {
        struct Stat { var value: String; var count: Int; var last: Date }
        var stats: [String: Stat] = [:]
        for (raw, date) in uses {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let key = value.lowercased()
            if var stat = stats[key] {
                stat.count += 1
                stat.last = max(stat.last, date)
                stats[key] = stat
            } else {
                stats[key] = Stat(value: value, count: 1, last: date)
            }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let excluded = Set(excluding.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } + [q])
        let ranked = stats.filter { !excluded.contains($0.key) }.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.last != $1.last { return $0.last > $1.last }
            return $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending
        }
        guard !q.isEmpty else { return ranked.prefix(limit).map(\.value) }
        func isPrefix(_ value: String) -> Bool {
            let lower = value.lowercased()
            return lower.hasPrefix(q) || lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(q) }
        }
        let prefix = ranked.filter { isPrefix($0.value) }
        let substring = ranked.filter { !isPrefix($0.value) && $0.value.lowercased().contains(q) }
        return (prefix + substring).prefix(limit).map(\.value)
    }
}
```

```swift
// ImportText.swift
import Foundation

public enum PhotosCleanupText {
    public static func prompt(count: Int) -> String {
        count == 1 ? "Delete this video from Photos?" : "Delete \(count) videos from Photos?"
    }
    public static let detail = "They'll also leave iCloud Photos, so Repaso will have the only copy."
    public static let removed = "Removed from Photos"
    public static let kept = "Kept in Photos"
    public static let failed = "Couldn't remove from Photos"
    public static let needsAccess = "Allow full Photos access in Settings to delete"
}

public enum ImportSummary {
    /// "Recorded Oct 12, 2026", or a span when the batch covers several days.
    public static func recordedLine(_ dates: [Date], calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        if calendar.isDate(first, inSameDayAs: last) {
            var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar)
            style.timeZone = calendar.timeZone
            return "Recorded " + first.formatted(style)
        }
        var style = Date.IntervalFormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        return "Recorded " + (first..<last).formatted(style)
    }
}
```

- [ ] **Step 4: Run** → all pass.

---

### Task 3: ClipExport + ClipExporter

**Files:**
- Create: `Packages/RepasoCore/Sources/RepasoCore/Export/ClipExport.swift`, `ClipExporter.swift`
- Create: `Packages/RepasoCore/Tests/RepasoCoreTests/ExportTests.swift`

**Interfaces:**
- Produces: `ClipExport.fileName(for:) -> String`, `ClipExport.timeRange(start:end:duration:) -> ClosedRange<Double>`, `ClipExporter.export(source:range:to:progress:) async throws`.

- [ ] **Step 1: Failing tests**

```swift
import Testing
import Foundation
@testable import RepasoCore

struct ExportTests {
    @Test func fileNameSanitises() {
        #expect(ClipExport.fileName(for: "Hammerlock exit") == "Hammerlock exit.mp4")
        #expect(ClipExport.fileName(for: "Turn 1/2: prep") == "Turn 1-2- prep.mp4")
        #expect(ClipExport.fileName(for: "   ") == "Clip.mp4")
        #expect(ClipExport.fileName(for: String(repeating: "a", count: 80)) == String(repeating: "a", count: 60) + ".mp4")
    }

    @Test func timeRangeClamps() {
        #expect(ClipExport.timeRange(start: -1, end: 5, duration: 10) == 0...5)
        #expect(ClipExport.timeRange(start: 8, end: 20, duration: 10) == 8...10)
        #expect(ClipExport.timeRange(start: 4, end: 4, duration: 10) == 4...4.1)
    }

    @Test func exportsOnlyTheRange() async throws {
        let dir = try TestVideo.tempDir()
        let source = try await TestVideo.make(seconds: 3, in: dir)
        let out = dir.appendingPathComponent("out.mp4")
        try await ClipExporter.export(source: source, range: 1...2, to: out) { _ in }
        let meta = try await VideoMetadata.load(out)
        #expect(abs(meta.duration - 1) < 0.15)
    }
}
```

- [ ] **Step 2: Run** → fails.

- [ ] **Step 3: Implement**

```swift
// ClipExport.swift
import Foundation

public enum ClipExport {
    public static let minimumLength = 0.1

    /// A share-safe "<clip name>.mp4".
    public static func fileName(for clipName: String) -> String {
        let illegal = Set("/\\:?*\"<>|")
        let cleaned = String(clipName.map { illegal.contains($0) ? "-" : $0 })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = String(cleaned.prefix(60)).trimmingCharacters(in: .whitespacesAndNewlines)
        return (base.isEmpty ? "Clip" : base) + ".mp4"
    }

    public static func timeRange(start: Double, end: Double, duration: Double) -> ClosedRange<Double> {
        let lower = min(max(0, start), max(0, duration - minimumLength))
        let upper = min(max(end, lower + minimumLength), max(duration, lower + minimumLength))
        return lower...upper
    }
}
```

```swift
// ClipExporter.swift
import AVFoundation

/// Writes just a clip's range of its original to an .mp4 for sharing.
public enum ClipExporter {
    public enum ExportError: Error { case unavailable }

    public static func export(source: URL, range: ClosedRange<Double>, to destination: URL,
                              progress: @escaping @Sendable (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: destination)
        let asset = AVURLAsset(url: source)
        // HighestQuality re-encodes, so the clip starts on the exact frame (passthrough snaps to keyframes).
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.unavailable
        }
        session.timeRange = CMTimeRange(start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                                        end: CMTime(seconds: range.upperBound, preferredTimescale: 600))
        let watcher = Task {
            for await state in session.states(updateInterval: 0.1) {
                if case .exporting(let p) = state { progress(p.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        do {
            try await session.export(to: destination, as: .mp4)
            progress(1)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
```

- [ ] **Step 4: Run** → pass.

---

### Task 4: Drag infrastructure + Home reorder

**Files:**
- Create: `Repaso/DragDrop/DragRef.swift`, `Repaso/DragDrop/DragState.swift`, `Repaso/DragDrop/DragModifiers.swift` (DragSource, `dragTarget`, `Jiggle`), `Repaso/DragDrop/LiftPreviews.swift`
- Modify: `project.yml` (UTExportedTypeDeclarations), `Repaso/App/AppEnvironment.swift` (`let drag = DragState()`), `Repaso/Home/HomeView.swift`

**Interfaces:**
- Produces: `DragRef(kind: .folder|.clip, id:)`; `DragState.active: DragRef?`, `.origin: UUID?`, `begin(_:from:)`, `end()`, `setTargeted(_:)`; `View.dragSource(_:drag:origin:preview:)`, `View.dragTarget(_:isTargeted:perform:)`, `View.jiggle(_:)`.
- Consumes: `FolderOrder.moving`, `LibraryService.setFolderOrder`.

> **Changed during execution:** `begin(_:from:)` became `lift(_:from:)` + `activate()`. The payload closure also runs when the user only opens a context menu, so a lift stays pending until the session moves (iOS 27 phase or first hover) and expires after 2.5s. See spec §4.2 and `Repaso/DragDrop/DragState.swift`.

Key code:

```swift
// DragRef.swift
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Declared in project.yml (UTExportedTypeDeclarations), so only Repaso's own targets accept these drags.
    static let repasoDragRef = UTType(exportedAs: "com.amudgal.repaso.drag-ref", conformingTo: .data)
}

struct DragRef: Codable, Hashable, Transferable {
    enum Kind: String, Codable { case folder, clip }
    let kind: Kind
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .repasoDragRef)
    }
}
```

```swift
// DragState.swift
import Foundation
import Observation

/// Which item is being dragged, and when the drag ends (spec §4.4).
@Observable @MainActor
final class DragState {
    private(set) var active: DragRef?
    /// The folder screen the drag started on (nil = Home or Unsorted).
    private(set) var origin: UUID?
    private var targeted = 0
    private var endCheck: Task<Void, Never>?

    func begin(_ ref: DragRef, from origin: UUID?) {
        endCheck?.cancel()
        targeted = 0
        self.origin = origin
        active = ref
    }

    func end() {
        endCheck?.cancel()
        targeted = 0
        active = nil
        origin = nil
    }

    /// iOS 26 fallback: drop targets and screen catchers report hover here; zero for 0.3s means the drag is over.
    func setTargeted(_ isTargeted: Bool) {
        guard active != nil else { return }
        targeted = max(0, targeted + (isTargeted ? 1 : -1))
        endCheck?.cancel()
        guard targeted == 0 else { return }
        endCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled, let self, self.targeted == 0 else { return }
            self.end()
        }
    }
}
```

`project.yml` → under `targets.Repaso.info.properties`:

```yaml
        UTExportedTypeDeclarations:
          - UTTypeIdentifier: com.amudgal.repaso.drag-ref
            UTTypeDescription: Repaso item
            UTTypeConformsTo: [public.data]
```

Home: `liveOrder: [UUID]?`; `displayedFolders` built from it; each card `dragSource(.folder)` + `dragTarget` whose `isTargeted(true)` runs `FolderOrder.moving`; the ScrollView gets a catcher `dragTarget`; `.onChange(of: env.drag.active)` seeds `liveOrder` at lift and commits `setFolderOrder(displayedFolders)` + settle keyframes when a folder drag ends; the dragged card renders as a dashed placeholder; others `.jiggle(isDraggingFolder)`; subtitle `Drop to place` in green.

- [ ] Build with zero warnings; manual drag check in the walkthrough (Task 7).

---

### Task 5: Folder — drag a clip onto a subfolder (hover, ring, spring-load, absorb, Undo, screen drop)

**Files:**
- Modify: `Repaso/Components/ClipRow.swift` (`isDraggable`, drag source, dim when lifted, `share` action), `Repaso/Components/OriginalCard.swift` (pass `isDraggable`), `Repaso/Folder/FolderView.swift`
- Create: `Repaso/Folder/SubfolderDropCard.swift`

**Interfaces:**
- Consumes: `DragState`, `dragSource`, `dragTarget`, `LibraryService.dropClip/undo`, `env.showToast(_:undo:)`.

`SubfolderDropCard` wraps `FolderCard(compact:)`: pulse border while a clip drag is active; on hover scale 1.08, y −4, green border + tint, ring trims 0 → 1 over 0.9s linear; a hover `Task` sleeps 0.9s then fires `onSpringLoad`; `keyframeAnimator` for absorb keyed on `absorbCount`.

FolderView `drop(_ ref:on:)`:

```swift
private func drop(_ ref: DragRef, on target: Folder) -> Bool {
    guard ref.kind == .clip, let clip = fetchClip(ref.id) else { return false }
    let lib = env.library(ctx)
    var receipt: ClipMoveReceipt?
    env.perform { receipt = try withAnimation(Theme.spring) { try lib.dropClip(clip, on: target) } }
    guard let receipt else { return false }
    absorbCounts[target.id, default: 0] += 1
    dropSuccess += 1
    let env = env
    env.showToast("Moved to \(target.name)") {
        env.perform { try withAnimation(Theme.spring) { try lib.undo(receipt) } }
    }
    return true
}
```

Screen catcher: `.dragTarget(env.drag) { ref in env.drag.origin != folder.id && drop(ref, on: folder) }` on the ScrollView for real folders, plus a `Drop to file in <name>` banner when `env.drag.active?.kind == .clip && env.drag.origin != folder.id`. Section label switches to `Drop on a folder` (green).

- [ ] Build, zero warnings.

---

### Task 6: Share export + Import sheet (tags, recorded line, delete from Photos)

**Files:**
- Create: `Repaso/Sheets/ShareSheet.swift` (ShareSheet + ActivityView), `Repaso/Import/PhotosCleaner.swift`
- Modify: `Repaso/Folder/FolderSupport.swift` (`LibrarySheet.share`), `Repaso/Folder/FolderView.swift` + `FavoritesView` (share action), `Repaso/Player/PlayerView.swift` (Share button, tag source line), `Repaso/Components/OriginalCard.swift` (event in meta), `Repaso/Import/ImportCoordinator.swift`, `Repaso/Import/ImportSheet.swift`, `Repaso/Home/HomeView.swift` + `FolderView.swift` (`photoLibrary: .shared()`), `Repaso/App/RepasoApp.swift` (clear `tmp/Exports` at launch), `project.yml` (Photos usage string mentions deleting).

ImportCoordinator additions: `Item.assetID`, `Item.originalID`, `Item.recordedAt`; `instructorsText`, `eventText`, `photosResult: String?`; `isFinished`, `deletableAssetIDs`, `showPhotosPrompt`; `applyTags(context:env:)`, `keepInPhotos()`, `deleteFromPhotos() async`. New originals are inserted with `TagText.instructors(from: instructorsText)` and `eventText`.

```swift
// PhotosCleaner.swift
import Photos

enum PhotosCleaner {
    enum Outcome { case removed, kept, needsAccess, failed }

    static func delete(_ ids: [String]) async -> Outcome {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { return .needsAccess }
        guard PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).count > 0 else { return .needsAccess }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
            }
            return .removed
        } catch {
            return (error as? PHPhotosError)?.code == .userCancelled ? .kept : .failed
        }
    }
}
```

- [ ] Build, zero warnings; core tests still pass.

---

### Task 7: Walkthrough — drag-move + Undo, Home reorder; full verification

**Files:**
- Modify: `RepasoUITests/WalkthroughTests.swift`

After the Cut step (`app.buttons["Done"].tap()`), before the menu Move:

```swift
// Drag a clip onto a subfolder card, then Undo
XCTAssertTrue(wrap.waitForExistence(timeout: 5))
let hammerCard = button(beginningWith: "Hammerlock")
XCTAssertTrue(hammerCard.waitForExistence(timeout: 3))
wrap.press(forDuration: 0.8, thenDragTo: hammerCard, withVelocity: .slow, thenHoldForDuration: 0.3)
XCTAssertTrue(app.staticTexts["Moved to Hammerlock"].waitForExistence(timeout: 3))
XCTAssertEqual(app.staticTexts.matching(identifier: "In Hammerlock").count, 2)
snap("08-drag-moved")
app.buttons["Undo"].tap()
XCTAssertTrue(waitForCount(of: "In Hammerlock", toBe: 1))
```

And a Home reorder test (`testHomeReorderByDrag`): drag the Footwork card (first, newer) onto Turns, assert Turns's frame is now left of/above Footwork's; relaunch is not needed (in-memory store).

- [ ] **Run everything:** `DEVELOPER_DIR=… xcodegen generate && DEVELOPER_DIR=… xcodebuild test -project Repaso.xcodeproj -scheme Repaso -destination 'platform=iOS Simulator,name=iPhone 18 Pro'` with `seed.mov` in the app container. Expected: all core tests, SmokeTests and WalkthroughTests pass; `grep -c "warning:"` on the build log for our sources is 0.
