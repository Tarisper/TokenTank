import Foundation
import Testing
@testable import TokenTankKit

struct UsageChunkingTests {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func windowsAreAlignedToPeriodStartAndLimitedInDays() throws {
        let calendar = utcCalendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let windows = UsageChunking.windows(in: Period(start: start, end: end), calendar: calendar)
        #expect(windows.count == 2)
        #expect(windows[0].start == start)
        #expect(windows[0].end == calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        #expect(windows[1].start == calendar.date(from: DateComponents(year: 2026, month: 10, day: 2)))
        #expect(windows[1].end == end)
    }

    @Test func shortPeriodProducesSingleWindow() throws {
        let calendar = utcCalendar
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5))!
        let windows = UsageChunking.windows(in: Period(start: start, end: end), calendar: calendar)
        #expect(windows.count == 1)
        #expect(windows[0].start == start)
        #expect(windows[0].end == end)
    }

    @Test func mergeDeduplicatesSeamsByLocalDay() {
        func usage(_ day: String, requests: Int) -> DailyUsage {
            DailyUsage(localDay: day, timeZoneID: "UTC", requests: requests, tokensIn: nil, tokensOut: nil, cost: nil, models: nil)
        }
        let merged = UsageChunking.merge([
            [usage("2026-10-01", requests: 2)],
            [usage("2026-10-01", requests: 9), usage("2026-10-02", requests: 3)],
        ])
        #expect(merged.map(\.localDay) == ["2026-10-01", "2026-10-02"])
        #expect(merged.first?.requests == 2)
    }
}
