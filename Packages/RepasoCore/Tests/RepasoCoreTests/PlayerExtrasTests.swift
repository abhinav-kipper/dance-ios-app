import Testing
import Foundation
import SwiftData
@testable import RepasoCore

struct PlayerGestureTests {
    @Test func classifiesByPriority() {
        #expect(PlayerGesture.classify(dx: 5, dy: 5, isZoomed: true, isPlaying: true) == .pan)
        #expect(PlayerGesture.classify(dx: 3, dy: -20, isZoomed: false, isPlaying: true) == .swipe)
        #expect(PlayerGesture.classify(dx: 12, dy: 2, isZoomed: false, isPlaying: false) == .scrub)
        #expect(PlayerGesture.classify(dx: 12, dy: 2, isZoomed: false, isPlaying: true) == nil)
        #expect(PlayerGesture.classify(dx: 2, dy: 10, isZoomed: false, isPlaying: false) == nil)
    }
    @Test func swipeCommitsPast80() {
        #expect(PlayerGesture.swipeDirection(dy: -81) == 1)
        #expect(PlayerGesture.swipeDirection(dy: 81) == -1)
        #expect(PlayerGesture.swipeDirection(dy: -79) == 0)
    }
    @Test func framesPerFivePoints() {
        #expect(PlayerGesture.frames(forDrag: 12) == 2)
        #expect(PlayerGesture.frames(forDrag: -12) == -2)
        #expect(PlayerGesture.frames(forDrag: 4) == 0)
    }
    @Test func queueStopsAtEnds() {
        #expect(ClipQueue.step(from: 0, by: 1, count: 3) == 1)
        #expect(ClipQueue.step(from: 2, by: 1, count: 3) == nil)
        #expect(ClipQueue.step(from: 0, by: -1, count: 3) == nil)
    }
    @Test func frameLabel() {
        #expect(TimeFormat.frame(412) == "Frame 0412")
        #expect(TimeFormat.frame(12345) == "Frame 12345")
    }
}

struct FramingTests {
    @Test func clampsZoomAndPan() {
        let f = Framing(zoom: 5, panX: 3, panY: -3).clamped()
        #expect(f.zoom == 3)
        #expect(f.panX == 1)
        #expect(f.panY == -1)
        #expect(Framing(zoom: 2, panX: 0.8, panY: 0).clamped().panX == 0.5)
    }
    @Test func nearOneSnapsToIdentity() {
        #expect(Framing(zoom: 1.005, panX: 0.2, panY: 0.1).clamped() == .identity)
        #expect(!Framing.identity.isZoomed)
        #expect(Framing(zoom: 1.6, panX: 0, panY: 0).label == "1.6×")
    }
}

struct PreviewBudgetTests {
    @Test func capsAndPromotes() {
        var b = PreviewBudget<Int>(capacity: 2)
        for i in 1...3 { b.request(i) }
        b.request(1)
        #expect(b.granted == [1, 2])
        #expect(b.waiting == [3])
        b.release(1)
        #expect(b.granted == [2, 3])
        #expect(b.waiting.isEmpty)
    }
    @Test func disableParksAndReenableGrants() {
        var b = PreviewBudget<Int>(capacity: 2)
        b.request(1); b.request(2); b.request(3)
        b.setEnabled(false)
        #expect(b.granted.isEmpty)
        #expect(b.waiting == [1, 2, 3])
        b.request(4)
        #expect(b.granted.isEmpty)
        b.setEnabled(true)
        #expect(b.granted == [1, 2])
        #expect(b.isGranted(2) && !b.isGranted(3))
    }
}

@MainActor
struct FramingLibraryTests {
    @Test func setFramingPersistsClamped() throws {
        let ctx = try makeContext()
        let lib = LibraryService(context: ctx)
        let o = try lib.addOriginal(title: "T", fileName: "t.mov", duration: 100, recordedAt: nil, to: nil)
        let c = try lib.addClip(to: o, start: 10, end: 20)
        try lib.setFraming(c, Framing(zoom: 4, panX: 2, panY: 0))
        #expect(c.framing == Framing(zoom: 3, panX: 1, panY: 0))
        #expect(c.previewSource?.range == 10...13)
        #expect(o.previewSource.range == 30...33)
    }
}
