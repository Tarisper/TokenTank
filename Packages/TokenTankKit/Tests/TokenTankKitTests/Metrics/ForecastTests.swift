import Foundation
import Testing
@testable import TokenTankKit

struct ForecastTests {
    private func point(_ day: String, _ available: Decimal, currency: String = "CNY") -> BalancePoint {
        BalancePoint(localDay: day, timeZoneID: "UTC", available: available, currency: currency)
    }

    @Test func computesDaysLeftFromMeanBurn() {
        let history = [point("2026-11-01", 100), point("2026-11-02", 90), point("2026-11-03", 80), point("2026-11-04", 70)]
        #expect(Forecast.daysLeft(history: history, currency: "CNY") == .days(7))
    }

    @Test func excludesTopUpDays() {
        let history = [
            point("2026-11-01", 100),
            point("2026-11-02", 90),
            point("2026-11-03", 120),
            point("2026-11-04", 110),
            point("2026-11-05", 100),
        ]
        #expect(Forecast.daysLeft(history: history, currency: "CNY") == .days(10))
    }

    @Test func needsAtLeastThreeValidDays() {
        let history = [point("2026-11-01", 100), point("2026-11-02", 90)]
        #expect(Forecast.daysLeft(history: history, currency: "CNY") == .notEnoughData)
    }

    @Test func flatSeriesHasNoForecast() {
        let history = [point("2026-11-01", 50), point("2026-11-02", 50), point("2026-11-03", 50), point("2026-11-04", 50)]
        #expect(Forecast.daysLeft(history: history, currency: "CNY") == .notEnoughData)
    }

    @Test func ignoresOtherCurrencies() {
        let history = [point("2026-11-01", 100, currency: "USD"), point("2026-11-02", 90, currency: "USD")]
        #expect(Forecast.daysLeft(history: history, currency: "CNY") == .notEnoughData)
    }

    @Test func weeklyObservationsDoNotCountAsDailyBurn() {
        let history = [point("2026-10-24", 100), point("2026-10-31", 90), point("2026-11-07", 80), point("2026-11-14", 70)]
        #expect(Forecast.daysLeft(history: history, currency: "CNY") == .notEnoughData)
    }

    @Test func observationsOutsideCalendarWindowAreExcluded() {
        let history = [point("2026-10-01", 100), point("2026-10-02", 90), point("2026-10-03", 80), point("2026-10-04", 70), point("2026-11-14", 60)]
        #expect(Forecast.daysLeft(history: history, currency: "CNY") == .notEnoughData)
    }

    @Test func missingDaysAreExcludedFromDailyBurn() {
        let history = [point("2026-11-01", 100), point("2026-11-02", 90), point("2026-11-05", 60), point("2026-11-06", 50), point("2026-11-07", 40)]
        #expect(Forecast.daysLeft(history: history, currency: "CNY") == .days(4))
    }
}
