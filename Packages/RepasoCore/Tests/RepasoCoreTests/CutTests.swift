import Foundation
import Testing
@testable import RepasoCore

struct CutTests {
    @Test func markCreatesRange() {
        var s = CutSession(duration: 768)
        #expect(s.mark(at: 200) == nil)
        #expect(s.isRecording)
        #expect(s.liveLength(at: 204.23) == 4.2)
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
