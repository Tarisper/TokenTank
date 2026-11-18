import Foundation
import Testing
@testable import TokenTankKit

struct WidgetReloadGateTests {
    private func file(updatedAt: Date = Date(timeIntervalSince1970: 1_000), balance: Decimal = 100) -> SnapshotFile {
        SnapshotFile(updatedAt: updatedAt, accounts: [
            AccountSnapshot(
                accountID: UUID(uuidString: "6F1E4B2C-8A44-4A0B-9E67-1B7A3F0D2C11")!,
                updatedAt: updatedAt,
                isAvailable: true,
                balances: [Money(role: .available, amount: balance, currency: "CNY")],
                quotas: nil,
                usageHistory: nil,
                balanceHistory: nil,
                limits: nil,
                modelTopByScope: nil,
                sections: [SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: updatedAt, lastAttemptAt: updatedAt)]
            )
        ])
    }

    @Test func volatileTimestampsDoNotTriggerReload() {
        var gate = WidgetReloadGate(minimumInterval: 300)
        let now = Date(timeIntervalSince1970: 5_000)
        #expect(gate.shouldReload(file: file(updatedAt: now), now: now) == true)
        // Same content, different timestamps — no reload (§2).
        #expect(gate.shouldReload(file: file(updatedAt: now.addingTimeInterval(900)), now: now.addingTimeInterval(900)) == false)
    }

    @Test func twoChangesProduceOneReloadAfterTheWindow() {
        var gate = WidgetReloadGate(minimumInterval: 300)
        let t0 = Date(timeIntervalSince1970: 5_000)
        #expect(gate.shouldReload(file: file(balance: 100), now: t0) == true)
        // Change inside the window: remembered, reload deferred (M4 remark 3).
        #expect(gate.shouldReload(file: file(balance: 90), now: t0.addingTimeInterval(120)) == false)
        // Next call after the window fires the pending reload, even unchanged.
        #expect(gate.shouldReload(file: file(balance: 90), now: t0.addingTimeInterval(400)) == true)
        #expect(gate.shouldReload(file: file(balance: 90), now: t0.addingTimeInterval(800)) == false)
    }

    @Test func contentChangeAfterWindowReloadsImmediately() {
        var gate = WidgetReloadGate(minimumInterval: 300)
        let t0 = Date(timeIntervalSince1970: 5_000)
        #expect(gate.shouldReload(file: file(balance: 100), now: t0) == true)
        #expect(gate.shouldReload(file: file(balance: 80), now: t0.addingTimeInterval(600)) == true)
    }

    @Test func explicitRefreshBypassesWindowAndTimestampFilter() {
        var gate = WidgetReloadGate(minimumInterval: 300)
        let t0 = Date(timeIntervalSince1970: 5_000)
        #expect(gate.shouldReload(file: file(updatedAt: t0), now: t0) == true)
        let refreshed = file(updatedAt: t0.addingTimeInterval(10))
        #expect(gate.shouldReload(file: refreshed, now: t0.addingTimeInterval(10), force: true) == true)
        #expect(gate.shouldReload(file: refreshed, now: t0.addingTimeInterval(400)) == false)
    }

    @Test func explicitRefreshConsumesPendingChangeAndResetsWindow() {
        var gate = WidgetReloadGate(minimumInterval: 300)
        let t0 = Date(timeIntervalSince1970: 5_000)
        #expect(gate.shouldReload(file: file(balance: 100), now: t0) == true)
        #expect(gate.shouldReload(file: file(balance: 90), now: t0.addingTimeInterval(10)) == false)
        #expect(gate.shouldReload(file: file(balance: 90), now: t0.addingTimeInterval(20), force: true) == true)
        #expect(gate.shouldReload(file: file(balance: 80), now: t0.addingTimeInterval(310)) == false)
        #expect(gate.shouldReload(file: file(balance: 80), now: t0.addingTimeInterval(320)) == true)
        #expect(gate.shouldReload(file: file(balance: 80), now: t0.addingTimeInterval(700)) == false)
    }

}
