import Foundation
import Testing
@testable import RepasoCore

struct CutStripTests {
    @Test func zoomClampsToVideoAndLimits() {
        #expect(CutStrip.clampVisible(30, duration: 600) == 30)
        #expect(CutStrip.clampVisible(2, duration: 600) == 8)
        #expect(CutStrip.clampVisible(1000, duration: 600) == 300)
        #expect(CutStrip.clampVisible(60, duration: 20) == 20)      // never wider than the video
        #expect(CutStrip.clampVisible(60, duration: 3) == 8)        // tiny video: the minimum still applies
        #expect(CutStrip.clampVisible(.nan, duration: 600) == 30)
    }

    @Test func offsetAndTimeRoundTrip() {
        let pps = CutStrip.pointsPerSecond(visible: 30, width: 360)   // 12 pt/s
        #expect(pps == 12)
        #expect(CutStrip.offset(for: 125, pointsPerSecond: pps, duration: 600) == 1500)
        #expect(CutStrip.time(forOffset: 1500, pointsPerSecond: pps, duration: 600) == 125)
    }

    @Test func timeAndOffsetClampToVideo() {
        #expect(CutStrip.time(forOffset: -40, pointsPerSecond: 12, duration: 600) == 0)
        #expect(CutStrip.time(forOffset: 99_999, pointsPerSecond: 12, duration: 600) == 600)
        #expect(CutStrip.offset(for: 700, pointsPerSecond: 12, duration: 600) == 7200)
        #expect(CutStrip.time(forOffset: .nan, pointsPerSecond: 12, duration: 600) == 0)
    }

    @Test func contentIsPaddedByOneScreen() {
        #expect(CutStrip.contentWidth(duration: 600, pointsPerSecond: 12, visibleWidth: 360) == 7560)
    }

    @Test func tilesStayAtLeastTargetWidth() {
        #expect(CutStrip.tileSpan(pointsPerSecond: 12) == 5)       // 4s would be 48pt, but 3s is 36pt: next span up
        #expect(CutStrip.tileSpan(pointsPerSecond: 100) == 0.5)
        #expect(CutStrip.tileSpan(pointsPerSecond: 0.01) == 300)
        #expect(CutStrip.tileCount(duration: 61, span: 5) == 13)
        #expect(CutStrip.tileCount(duration: 0, span: 5) == 0)
    }
}
