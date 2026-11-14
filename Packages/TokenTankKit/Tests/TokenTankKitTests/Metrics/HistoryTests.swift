import Foundation
import Testing
@testable import TokenTankKit

struct HistoryTests {
    private func point(_ day: String, _ available: Decimal, currency: String = "CNY", tz: String = "UTC") -> BalancePoint {
        BalancePoint(localDay: day, timeZoneID: tz, available: available, currency: currency)
    }

    private func usage(_ day: String, tokens: Int) -> DailyUsage {
        DailyUsage(localDay: day, timeZoneID: "UTC", requests: 1, tokensIn: tokens, tokensOut: 0, cost: nil, models: nil)
    }

    @Test func balancePointsAppendPerCurrency() {
        let balances = [
            Money(role: .available, amount: 10, currency: "CNY"),
            Money(role: .available, amount: 20, currency: "USD"),
            Money(role: .cash, amount: 5, currency: "CNY"),
        ]
        let result = BalanceHistory.appending(
            history: [],
            balances: balances,
            at: Date(timeIntervalSince1970: 1_000_000),
            timeZoneID: "UTC"
        )
        #expect(result.count == 2)
        #expect(Set(result.map(\.currency)) == ["CNY", "USD"])
    }

    @Test func sameDayPointIsReplaced() {
        let history = [point("1970-01-12", 100)]
        let result = BalanceHistory.appending(
            history: history,
            balances: [Money(role: .available, amount: 90, currency: "CNY")],
            at: Date(timeIntervalSince1970: 1_000_000),
            timeZoneID: "UTC"
        )
        #expect(result.filter { $0.currency == "CNY" }.count == 1)
    }

    @Test func seriesTrimToNinetyDaysDroppingOldest() {
        let history = (1...95).map { point(String(format: "2026-%03d", $0), Decimal($0)) }
        let trimmed = BalanceHistory.trimmed(history)
        #expect(trimmed.count == 90)
        #expect(trimmed.first?.available == 6)
    }

    @Test func dayBoundaryFollowsProviderTimeZone() {
        // 20:00 UTC is already the next day in Asia/Shanghai.
        let date = Date(timeIntervalSince1970: 1_794_609_600) // 2026-11-13 20:00 UTC
        let utc = BalanceHistory.appending(history: [], balances: [Money(role: .available, amount: 1, currency: "CNY")], at: date, timeZoneID: "UTC")
        let cst = BalanceHistory.appending(history: [], balances: [Money(role: .available, amount: 1, currency: "CNY")], at: date, timeZoneID: "Asia/Shanghai")
        #expect(utc.first?.localDay != cst.first?.localDay)
    }

    @Test func usageMergeDeduplicatesByLocalDayWithIncomingWins() {
        let merged = UsageHistory.merging(
            existing: [usage("2026-11-01", tokens: 100), usage("2026-11-02", tokens: 200), usage("2026-11-03", tokens: 300)],
            incoming: [usage("2026-11-03", tokens: 999), usage("2026-11-04", tokens: 400)],
            retentionDays: 3
        )
        #expect(merged.map(\.localDay) == ["2026-11-02", "2026-11-03", "2026-11-04"])
        #expect(merged.first { $0.localDay == "2026-11-03" }?.tokensIn == 999)
    }

    @Test func usageRetentionExtendsToQuotaPeriod() {
        #expect(UsageHistory.retentionDays(quotaPeriodDays: nil) == 90)
        #expect(UsageHistory.retentionDays(quotaPeriodDays: 30) == 90)
        #expect(UsageHistory.retentionDays(quotaPeriodDays: 365) == 365)
        #expect(HistoryPolicy.usageRetentionDays(quotas: nil) == 90)
        let quota = Quota(
            id: "q",
            kind: .tokenPlan,
            unit: .credits,
            total: 1,
            used: 0,
            remaining: 1,
            period: Period(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 365 * 86_400)),
            autoRenew: nil
        )
        #expect(HistoryPolicy.usageRetentionDays(quotas: [quota]) == 365)
    }

    @Test func startupCleanupTrimsHistories() {
        let longHistory = (1...95).map { point(String(format: "2026-%02d-01", 1), Decimal($0)) }
        let snapshot = AccountSnapshot(
            accountID: UUID(),
            updatedAt: Date(),
            isAvailable: true,
            balances: nil,
            quotas: nil,
            usageHistory: (1...200).map { usage(String(format: "2026-%03d", $0), tokens: $0) },
            balanceHistory: longHistory,
            limits: nil,
            modelTopByScope: nil,
            sections: []
        )
        let cleaned = HistoryPolicy.cleanup(snapshot)
        #expect(cleaned.balanceHistory?.count == 90)
        #expect(cleaned.usageHistory?.count == 90)
    }

    @Test func topModelsAggregateSumAndRankByCost() {
        func model(_ name: String, tokens: Int, cost: Decimal?) -> ModelUsage {
            ModelUsage(
                model: name,
                requests: 1,
                tokens: tokens,
                cost: cost.map { Money(role: .cash, amount: $0, currency: "CNY") }
            )
        }
        let history = [
            DailyUsage(localDay: "2026-11-01", timeZoneID: "UTC", requests: nil, tokensIn: nil, tokensOut: nil, cost: nil,
                       models: [model("a", tokens: 10, cost: 5), model("b", tokens: 10, cost: 30)]),
            DailyUsage(localDay: "2026-11-02", timeZoneID: "UTC", requests: nil, tokensIn: nil, tokensOut: nil, cost: nil,
                       models: [model("a", tokens: 10, cost: 5), model("d", tokens: 10, cost: 20), model("c", tokens: 90, cost: nil)]),
        ]
        let top = TopModels.aggregate(history: history)
        #expect(top.map(\.model) == ["b", "d", "a"])
        #expect(top.first?.cost?.amount == 30)
        #expect(top.first { $0.model == "a" }?.cost?.amount == 10)
        #expect(TopModels.aggregate(history: history, count: 2).map(\.model) == ["b", "d"])
        #expect(TopModels.aggregate(history: history, count: -1).isEmpty)
    }
}
