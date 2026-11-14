import Foundation
import Testing
@testable import TokenTankKit

struct AlertingTests {
    private func moneyThreshold(_ value: Decimal, rearm: Decimal = 1.1) throws -> Threshold {
        try Threshold(currency: "CNY", unit: nil, quotaID: nil, value: value, rearmFraction: rearm)
    }

    private func snapshot(balances: [Money] = [], quotas: [Quota] = [], sections: [SectionSnapshot]? = nil) -> AccountSnapshot {
        AccountSnapshot(
            accountID: UUID(),
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isAvailable: true,
            balances: balances,
            quotas: quotas,
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: nil,
            sections: sections ?? [.balance, .quotas].map {
                SectionSnapshot(kind: $0, slotID: nil, status: .ok, lastSuccessAt: nil, lastAttemptAt: nil)
            }
        )
    }

    @Test func sawtoothTriggersOnlyOnceUntilRearm() throws {
        var monitor = ThresholdMonitor(threshold: try moneyThreshold(100))
        // Sawtooth around the threshold: exactly one crossing, no repeats
        // until a full re-arm above 100 × 1.1 = 110 (§10).
        #expect(monitor.update(value: 150) == .none)
        #expect(monitor.update(value: 90) == .crossed)
        #expect(monitor.update(value: 95) == .none)
        #expect(monitor.update(value: 105) == .none)
        #expect(monitor.update(value: 110) == .none)
        #expect(monitor.update(value: 111) == .rearmed)
        #expect(monitor.update(value: 90) == .crossed)
        #expect(monitor.update(value: 109) == .none)
    }

    @Test func thresholdEvaluationIsIndependentPerCurrency() throws {
        var evaluator = ThresholdEvaluator()
        let cny = try Threshold(currency: "CNY", unit: nil, quotaID: nil, value: 500, rearmFraction: 1.1)
        let usd = try Threshold(currency: "USD", unit: nil, quotaID: nil, value: 500, rearmFraction: 1.1)
        let first = snapshot(balances: [
            Money(role: .available, amount: 400, currency: "CNY"),
            Money(role: .available, amount: 600, currency: "USD"),
        ])
        let triggers = evaluator.update(snapshot: first, thresholds: [cny, usd])
        #expect(triggers.map(\.event) == [.crossed])
        #expect(triggers.first?.threshold.currency == "CNY")
    }

    @Test func evaluatorDedupsRepeatsAndRearms() throws {
        var evaluator = ThresholdEvaluator()
        let threshold = try moneyThreshold(100)
        let low = snapshot(balances: [Money(role: .available, amount: 90, currency: "CNY")])
        let high = snapshot(balances: [Money(role: .available, amount: 120, currency: "CNY")])
        #expect(evaluator.update(snapshot: low, thresholds: [threshold]).map(\.event) == [.crossed])
        #expect(evaluator.update(snapshot: low, thresholds: [threshold]).isEmpty)
        #expect(evaluator.update(snapshot: high, thresholds: [threshold]).map(\.event) == [.rearmed])
    }

    @Test func triggeredPhaseSurvivesRestore() throws {
        let threshold = try moneyThreshold(100)
        let low = snapshot(balances: [Money(role: .available, amount: 90, currency: "CNY")])
        var first = ThresholdEvaluator()
        #expect(first.update(snapshot: low, thresholds: [threshold]).map(\.event) == [.crossed])
        // A restart must not repeat the alert that was already shown (§10 M5).
        var restored = ThresholdEvaluator(triggered: first.triggered)
        #expect(restored.update(snapshot: low, thresholds: [threshold]).isEmpty)
        let high = snapshot(balances: [Money(role: .available, amount: 120, currency: "CNY")])
        #expect(restored.update(snapshot: high, thresholds: [threshold]).map(\.event) == [.rearmed])
    }

    @Test func evaluatorDropsRemovedThresholdsFromState() throws {
        let kept = try moneyThreshold(100)
        let removed = try moneyThreshold(200)
        var evaluator = ThresholdEvaluator()
        let low = snapshot(balances: [Money(role: .available, amount: 90, currency: "CNY")])
        #expect(evaluator.update(snapshot: low, thresholds: [kept, removed]).count == 2)
        #expect(evaluator.triggered.count == 2)
        _ = evaluator.update(snapshot: low, thresholds: [kept])
        #expect(evaluator.triggered.count == 1)
    }

    @Test func thresholdStateStoreRoundTrip() {
        let suite = "ThresholdStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ThresholdStateStore(defaults: defaults)
        let accountID = UUID()
        #expect(store.triggered(for: accountID).isEmpty)
        store.setTriggered(["a|credits|1|1.1", "b"], for: accountID)
        #expect(store.triggered(for: accountID) == ["a|credits|1|1.1", "b"])
        store.setTriggered([], for: accountID)
        #expect(store.triggered(for: accountID).isEmpty)
    }

    @Test func quotaThresholdUsesRemaining() throws {
        var evaluator = ThresholdEvaluator()
        let threshold = try Threshold(currency: nil, unit: .credits, quotaID: "q1", value: 100, rearmFraction: 1.1)
        let quota = Quota(id: "q1", kind: .tokenPlan, unit: .credits, total: 1000, used: 950, remaining: 50, period: nil, autoRenew: nil)
        let triggers = evaluator.update(snapshot: snapshot(quotas: [quota]), thresholds: [threshold])
        #expect(triggers.map(\.event) == [.crossed])
        #expect(triggers.first?.value == 50)
    }

    @Test func partialFailuresOnlyAdvanceSuccessfulThresholds() throws {
        var evaluator = ThresholdEvaluator()
        let money = try moneyThreshold(100)
        let quotaThreshold = try Threshold(currency: nil, unit: .credits, quotaID: "q1", value: 100, rearmFraction: 1.1)
        let quota = Quota(id: "q1", kind: .tokenPlan, unit: .credits, total: 1000, used: 950, remaining: 50, period: nil, autoRenew: nil)
        let first = snapshot(balances: [Money(role: .available, amount: 90, currency: "CNY")], quotas: [quota], sections: [
            SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: nil, lastAttemptAt: nil),
            SectionSnapshot(kind: .quotas, slotID: "tp", status: .failed(.invalidKey), lastSuccessAt: nil, lastAttemptAt: nil),
            SectionSnapshot(kind: .usage, slotID: "sk", status: .failed(.server(status: 500)), lastSuccessAt: nil, lastAttemptAt: nil),
        ])
        let triggers = evaluator.update(snapshot: first, thresholds: [money, quotaThreshold])
        #expect(triggers.map(\.threshold) == [money])
        #expect(triggers.map(\.event) == [.crossed])
        let second = snapshot(balances: [Money(role: .available, amount: 120, currency: "CNY")], quotas: [quota], sections: [
            SectionSnapshot(kind: .balance, slotID: "sk", status: .failed(.network(code: -1009)), lastSuccessAt: nil, lastAttemptAt: nil),
            SectionSnapshot(kind: .quotas, slotID: "tp", status: .ok, lastSuccessAt: nil, lastAttemptAt: nil),
        ])
        let next = evaluator.update(snapshot: second, thresholds: [money, quotaThreshold])
        #expect(next.map(\.threshold) == [quotaThreshold])
        #expect(next.map(\.event) == [.crossed])
        #expect(evaluator.triggered.count == 2)
    }

    @Test func cachedSuccessAfterFailedPersistenceDoesNotTriggerAnAlert() throws {
        var evaluator = ThresholdEvaluator()
        let threshold = try moneyThreshold(100)
        let snapshot = snapshot(balances: [Money(role: .available, amount: 90, currency: "CNY")], sections: [
            SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: Date(timeIntervalSince1970: 1000), lastAttemptAt: Date(timeIntervalSince1970: 1000)),
        ])
        #expect(evaluator.update(snapshot: snapshot, thresholds: [threshold], attemptedAfter: Date(timeIntervalSince1970: 2000)).isEmpty)
        #expect(evaluator.triggered.isEmpty)
        #expect(evaluator.update(snapshot: snapshot, thresholds: [threshold], attemptedAfter: Date(timeIntervalSince1970: 500)).map(\.event) == [.crossed])
    }
}
