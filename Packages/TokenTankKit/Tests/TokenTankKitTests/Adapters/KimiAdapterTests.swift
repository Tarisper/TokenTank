import Foundation
import Testing
@testable import TokenTankKit

extension NetworkTests {
struct KimiAdapterTests {
    private func adminAccount(admin: Bool) -> AccountDescriptor {
        var slots = [CredentialSlot(id: "sk", kind: .apiKey, keychainRef: "ref-sk", baseURLOverride: nil)]
        if admin {
            slots.append(CredentialSlot(id: "admin", kind: .admin, keychainRef: "ref-admin", baseURLOverride: nil))
        }
        return testAccount(provider: .kimi, region: .cn, slots: slots)
    }

    private func codingAccount() -> AccountDescriptor {
        testAccount(provider: .kimi, region: .intl, slots: [
            CredentialSlot(id: "coding", kind: .coding, keychainRef: "ref-coding", baseURLOverride: nil),
        ])
    }

    @Test func balanceUsesRegionCurrency() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("kimi-balance")) }
        defer { URLProtocolStub.handler = nil }
        for (region, currency) in [(Region.cn, "CNY"), (Region.intl, "USD")] {
            let adapter = KimiAdapter(
                descriptor: testAccount(provider: .kimi, region: region),
                keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]),
                http: stubbedHTTPClient()
            )
            let snapshot = try await adapter.fetchPrimary(scope: .account).get()
            #expect(snapshot.balances?.allSatisfy { $0.currency == currency } == true)
            #expect(snapshot.balances?.count == 3)
            #expect(snapshot.balances?.contains(where: { $0.role == .available && $0.amount == Decimal(string: "49.58894")! }) == true)
        }
    }

    @Test func missingRegionMapsToRegionMismatch() async throws {
        let adapter = KimiAdapter(
            descriptor: testAccount(provider: .kimi, region: nil),
            keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]),
            http: stubbedHTTPClient()
        )
        await #expect(throws: ProviderError.regionMismatch) {
            _ = try await adapter.fetchPrimary(scope: .account).get()
        }
    }

    @Test func adminHistoryNormalizesHaofenAndUsesEpochMilliseconds() async throws {
        stubRequests { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/billings/daily_bills") {
                if request.url?.query?.contains("cursor=cursor-2") == true {
                    return .init(status: 200, body: fixture("kimi-admin-bills-page2"))
                }
                return .init(status: 200, body: fixture("kimi-admin-bills-page1"))
            }
            if path.hasSuffix("/usage/completions") {
                return .init(status: 200, body: fixture("kimi-admin-usage"))
            }
            return .init(status: 200, body: fixture("kimi-balance"))
        }
        defer { URLProtocolStub.handler = nil }

        let adapter = KimiAdapter(
            descriptor: adminAccount(admin: true),
            keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test", "ref-admin": "sk-admin-test"]),
            http: stubbedHTTPClient()
        )
        let snapshot = try await adapter.fetchAccount()
        #expect(snapshot.usageHistory?.map(\.localDay) == ["2026-11-11", "2026-11-12"])
        guard let day = snapshot.usageHistory?.first(where: { $0.localDay == "2026-11-11" }) else {
            Issue.record("expected day 2026-11-11")
            return
        }
        #expect(day.timeZoneID == "Asia/Shanghai")
        #expect(day.requests == 4)
        #expect(day.tokensIn == 1500)
        #expect(day.tokensOut == 600)
        #expect(day.cost == Money(role: .cash, amount: Decimal(string: "1.5")!, currency: "CNY"))
        #expect(day.models?.first?.cost == Money(role: .cash, amount: Decimal(string: "1.5")!, currency: "CNY"))
        #expect(day.models?.first?.requests == 4)
        #expect(day.models?.first?.tokens == 2100)

        let startValues = URLProtocolStub.requests.compactMap { request -> String? in
            guard let query = request.url?.query else { return nil }
            for pair in query.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.first == "start", parts.count == 2 { return String(parts[1]) }
            }
            return nil
        }
        #expect(startValues.allSatisfy { $0.count == 13 })
        #expect(URLProtocolStub.requests.contains { $0.url?.query?.contains("cursor=cursor-2") == true })
        let billRequests = URLProtocolStub.requests.filter { $0.url?.path.hasSuffix("/billings/daily_bills") == true }
        #expect(billRequests.count == 2)
    }

    @Test func adminDataNotReadyIsPerSectionFailure() async throws {
        stubRequests { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/billings/daily_bills") || path.hasSuffix("/usage/completions") {
                return .init(status: 400, body: fixture("kimi-admin-error-not-ready"))
            }
            return .init(status: 200, body: fixture("kimi-balance"))
        }
        defer { URLProtocolStub.handler = nil }

        let adapter = KimiAdapter(
            descriptor: adminAccount(admin: true),
            keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test", "ref-admin": "sk-admin-test"]),
            http: stubbedHTTPClient()
        )
        let snapshot = try await adapter.fetchAccount()
        guard case .ok = snapshot.sections.first(where: { $0.kind == .balance })?.status else {
            Issue.record("expected balance .ok")
            return
        }
        guard case .failed(.dataNotReady) = snapshot.sections.first(where: { $0.kind == .usage })?.status else {
            Issue.record("expected usage .failed(.dataNotReady)")
            return
        }
    }

    @Test func withoutAdminKeyUsageIsUnsupported() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("kimi-balance")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = KimiAdapter(
            descriptor: adminAccount(admin: false),
            keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]),
            http: stubbedHTTPClient()
        )
        let snapshot = try await adapter.fetchAccount()
        guard case .unsupported = snapshot.sections.first(where: { $0.kind == .usage })?.status else {
            Issue.record("expected usage .unsupported")
            return
        }
    }

    @Test func codingUsagesMapToMonthlyAndFiveHourPercentQuotas() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("kimi-coding-usages")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = KimiAdapter(
            descriptor: codingAccount(),
            keychain: InMemoryKeychain(storage: ["ref-coding": "sk-kimi-test"]),
            http: stubbedHTTPClient()
        )
        let snapshot = try await adapter.fetchAccount()
        #expect(snapshot.quotas?.map(\.id) == [KimiAdapter.codingMonthQuotaID, KimiAdapter.codingQuotaID])
        guard let month = snapshot.quotas?.first else {
            Issue.record("expected a monthly quota")
            return
        }
        #expect(month.kind == .subscription)
        #expect(month.unit == .percent)
        #expect(month.total == 100)
        #expect(month.used == Decimal(string: "78.03"))
        #expect(month.remaining == Decimal(string: "21.97"))
        #expect(month.period == nil)
        let monthReset = try Date("2026-12-02T00:00:00Z", strategy: .iso8601)
        #expect(month.resetsAt == monthReset)
        guard let fiveHour = snapshot.quotas?.last else {
            Issue.record("expected a 5-hour quota")
            return
        }
        #expect(fiveHour.unit == .percent)
        #expect(fiveHour.used == Decimal(string: "4.94"))
        #expect(fiveHour.remaining == Decimal(string: "95.06"))
        let resetsAt = try Date("2026-11-13T22:59:08Z", strategy: .iso8601)
        #expect(fiveHour.period?.end == resetsAt)
        #expect(fiveHour.period?.start == resetsAt.addingTimeInterval(-5 * 3600))
        #expect(fiveHour.resetsAt == nil)
        guard case .ok = snapshot.sections.first(where: { $0.kind == .quotas })?.status else {
            Issue.record("expected quotas .ok")
            return
        }
        #expect(snapshot.balances == nil)
        #expect(URLProtocolStub.requests.compactMap { $0.url?.absoluteString } == ["https://api.kimi.com/coding/v1/usages"])
    }

    @Test func codingUsagesWithoutLimitsUseFiveHourWindow() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("kimi-coding-usages-no-limits")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = KimiAdapter(
            descriptor: codingAccount(),
            keychain: InMemoryKeychain(storage: ["ref-coding": "sk-kimi-test"]),
            http: stubbedHTTPClient()
        )
        let snapshot = try await adapter.fetchAccount()
        #expect(snapshot.quotas?.map(\.id) == [KimiAdapter.codingMonthQuotaID, KimiAdapter.codingQuotaID])
        #expect(snapshot.sections.first(where: { $0.kind == .quotas })?.status == .ok)
        let fiveHour = try #require(snapshot.quotas?.last)
        let reset = try Date("2026-11-19T15:00:00Z", strategy: .iso8601)
        #expect(fiveHour.period?.end == reset)
        #expect(fiveHour.period?.start == reset.addingTimeInterval(-5 * 3600))
    }

    @Test func codingQuotaServesAccountAndQuotaScopes() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("kimi-coding-usages")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = KimiAdapter(
            descriptor: codingAccount(),
            keychain: InMemoryKeychain(storage: ["ref-coding": "sk-kimi-test"]),
            http: stubbedHTTPClient()
        )
        let fiveHour = try await adapter.fetchPrimary(scope: .quota(KimiAdapter.codingQuotaID)).get()
        #expect(fiveHour.quota?.used == Decimal(string: "4.94"))
        let accountScope = try await adapter.fetchPrimary(scope: .account).get()
        #expect(accountScope.quota?.id == KimiAdapter.codingMonthQuotaID)
    }

    @Test func codingUsagesWithoutLimitsFailClosed() async throws {
        stubRequests { _ in .init(status: 200, body: Data(#"{"limits":[]}"#.utf8)) }
        defer { URLProtocolStub.handler = nil }
        let adapter = KimiAdapter(
            descriptor: codingAccount(),
            keychain: InMemoryKeychain(storage: ["ref-coding": "sk-kimi-test"]),
            http: stubbedHTTPClient()
        )
        let snapshot = try await adapter.fetchAccount()
        guard case .failed(.decoding) = snapshot.sections.first(where: { $0.kind == .quotas })?.status else {
            Issue.record("expected quotas .failed(.decoding)")
            return
        }
        #expect(snapshot.quotas == nil)
    }

    @Test func emptyKeyIsRejectedWithoutARequest() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("kimi-balance")) }
        defer { URLProtocolStub.handler = nil }
        let slot = CredentialSlot(id: "coding", kind: .coding, keychainRef: "ref-coding", baseURLOverride: nil)
        await #expect(throws: ProviderError.invalidKey) {
            try await AdapterRegistry.validateKey("", slot: slot, provider: .kimi, region: .cn, http: stubbedHTTPClient())
        }
        #expect(URLProtocolStub.requests.isEmpty)
    }
}
}
