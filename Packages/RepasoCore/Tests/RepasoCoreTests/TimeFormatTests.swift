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
