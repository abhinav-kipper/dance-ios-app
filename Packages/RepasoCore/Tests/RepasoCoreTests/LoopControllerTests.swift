import Testing
@testable import RepasoCore

struct LoopControllerTests {
    @Test func defaultsRestart() {
        #expect(LoopController().actionAtEnd() == .restart)
    }

    @Test func gapCyclesAndDelays() {
        var l = LoopController()
        l.cycleGap()
        #expect(l.gap == .one)
        #expect(l.actionAtEnd() == .restartAfter(1))
        l.cycleGap()
        #expect(l.gap == .two)
        #expect(l.gap.label == "2s pause")
        l.cycleGap()
        #expect(l.gap == .none)
        #expect(l.gap.label == "No pause")
    }

    @Test func loopOffStops() {
        var l = LoopController()
        l.loopEnabled = false
        l.gap = .two
        #expect(l.actionAtEnd() == .stop)
    }
}
