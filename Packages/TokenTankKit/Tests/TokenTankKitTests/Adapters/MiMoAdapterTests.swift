import Foundation
import Testing
@testable import TokenTankKit

extension NetworkTests {
struct MiMoAdapterTests {
    private func account(sk: Bool = true, tp: Bool = false) -> AccountDescriptor {
        var slots: [CredentialSlot] = []
        if sk {
            slots.append(CredentialSlot(id: "sk", kind: .apiKey, keychainRef: "ref-sk", baseURLOverride: nil))
        }
        if tp {
            slots.append(CredentialSlot(id: "tp", kind: .tokenPlan, keychainRef: "ref-tp", baseURLOverride: nil))
        }
        return testAccount(provider: .mimo, slots: slots)
    }

    private let keys = InMemoryKeychain(storage: ["ref-sk": "sk-test", "ref-tp": "tp-test"])

    @Test func parsesBalanceRoles() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("mimo-balance")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = MiMoAdapter(descriptor: account(), keychain: keys, http: stubbedHTTPClient())
        let snapshot = try await adapter.fetchPrimary(scope: .account).get()
        #expect(snapshot.balances?.count == 6)
        #expect(snapshot.balances?.first == Money(role: .available, amount: Decimal(string: "500.50")!, currency: "CNY"))
        #expect(snapshot.balances?.contains(where: { $0.role == .cash && $0.amount == Decimal(string: "100.50")! }) == true)
        #expect(snapshot.balances?.contains(where: { $0.role == .creditAvailable && $0.amount == Decimal(string: "380.00")! }) == true)
    }

    @Test func unknownResponseFormFailsClosed() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("mimo-balance-unknown-form")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = MiMoAdapter(descriptor: account(), keychain: keys, http: stubbedHTTPClient())
        await #expect(throws: ProviderError.decoding) {
            _ = try await adapter.fetchPrimary(scope: .account).get()
        }
    }

    @Test func parsesTokenPlanQuotaAndPeriod() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("mimo-token-plan")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = MiMoAdapter(descriptor: account(tp: true), keychain: keys, http: stubbedHTTPClient())
        let snapshot = try await adapter.fetchPrimary(scope: .quota(MiMoAdapter.quotaID)).get()
        #expect(snapshot.scope == .quota(MiMoAdapter.quotaID))
        #expect(snapshot.quota?.id == MiMoAdapter.quotaID)
        #expect(snapshot.quota?.unit == .credits)
        #expect(snapshot.quota?.total == 4_100_000_000)
        #expect(snapshot.quota?.remaining == 4_099_000_000)
        #expect(snapshot.quota?.autoRenew == true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(snapshot.quota?.period?.start == calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        #expect(snapshot.quota?.period?.end == calendar.date(from: DateComponents(year: 2026, month: 10, day: 31)))
    }

    @Test func unknownQuotaScopeIsUnsupported() async throws {
        let adapter = MiMoAdapter(descriptor: account(tp: true), keychain: keys, http: stubbedHTTPClient())
        let result = await adapter.fetchPrimary(scope: .quota("bogus"))
        #expect(result == .failure(.unsupported))
    }

    @Test func tpOnlyAccountResolvesAccountScopeToQuota() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("mimo-token-plan")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = MiMoAdapter(descriptor: account(sk: false, tp: true), keychain: keys, http: stubbedHTTPClient())
        let snapshot = try await adapter.fetchPrimary(scope: .account).get()
        #expect(snapshot.scope == .quota(MiMoAdapter.quotaID))
        #expect(snapshot.quota != nil)
        #expect(snapshot.balances == nil)
    }

    @Test func usageChunksAlignToRetentionWindowAndDeduplicateSeams() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let day0 = formatter.string(from: now.addingTimeInterval(-90 * 86_400))
        let day30 = formatter.string(from: now.addingTimeInterval(-60 * 86_400))
        let day31 = formatter.string(from: now.addingTimeInterval(-59 * 86_400))

        func usageJSON(_ days: [String]) -> Data {
            let rows = days.map { day in
                "{\"date\": \"\(day)\", \"resource_type\": \"model\", \"name\": \"m\", \"currency\": \"CNY\", \"consumed_amount\": \"0.001000\", \"request_count\": 1}"
            }.joined(separator: ",")
            return Data("{\"object\": \"list\", \"data\": [\(rows)]}".utf8)
        }

        stubRequests { request in
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.hasSuffix("/usage/daily") {
                // The provider duplicates the seam day in both windows.
                if query.contains("start_date=\(day0)") {
                    return .init(status: 200, body: usageJSON([day0, day30]))
                }
                return .init(status: 200, body: usageJSON([day30, day31]))
            }
            return .init(status: 200, body: fixture("mimo-list-empty"))
        }
        defer { URLProtocolStub.handler = nil }

        let adapter = MiMoAdapter(descriptor: account(), keychain: keys, http: stubbedHTTPClient())
        let snapshot = try await adapter.fetchAccount()
        let usageQueries = URLProtocolStub.requests
            .map { $0.url?.query ?? "" }
            .filter { $0.contains("start_date") }
        #expect(usageQueries.count == 6)
        #expect(usageQueries.contains { $0.contains("start_date=\(day0)") && $0.contains("end_date=\(day30)") })
        #expect(usageQueries.contains { $0.contains("start_date=\(day31)") })
        // Seam day is deduplicated: first occurrence wins (M1.10).
        #expect(snapshot.usageHistory?.map(\.localDay) == [day0, day30, day31])
        guard case .ok = snapshot.sections.first(where: { $0.kind == .usage })?.status else {
            Issue.record("expected usage .ok")
            return
        }
    }

    @Test func usageWindowFollowsRetentionNotQuotaPeriod() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2025, month: 11, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let tokenPlan = """
        {"quota": {"total_credits": 100, "used_credits": 1, "remaining_credits": 99}, \
        "period": {"start_at": "2025-11-01 00:00:00", "end_at": "2026-11-01 00:00:00"}, \
        "auto_renew": false}
        """
        stubRequests { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/token_plan") {
                return .init(status: 200, body: Data(tokenPlan.utf8))
            }
            return .init(status: 200, body: fixture("mimo-list-empty"))
        }
        defer { URLProtocolStub.handler = nil }

        let adapter = MiMoAdapter(descriptor: account(tp: true), keychain: keys, http: stubbedHTTPClient())
        _ = try await adapter.fetchAccount()
        let usageQueries = URLProtocolStub.requests
            .compactMap { $0.url?.query }
            .filter { $0.contains("start_date") }
        #expect(usageQueries.isEmpty == false)
        // The quota period is 366 days, but the fetch window is the retention
        // window (90 days) — not the quota period (M6).
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.dateFormat = "yyyy-MM-dd"
        var allDates: [Date] = []
        for query in usageQueries {
            for pair in query.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                guard parts.count == 2, parts[0] == "start_date" || parts[0] == "end_date" else { continue }
                if let date = formatter.date(from: String(parts[1])) {
                    allDates.append(date)
                }
            }
        }
        let span = allDates.max()!.timeIntervalSince(allDates.min()!)
        #expect(span <= 91 * 86_400)
        #expect(allDates.min()! >= Date().addingTimeInterval(-95 * 86_400))
    }

    @Test func liveCapturedFixturesMatchDocumentedShapes() async throws {
        // §9.4: live-captured fixtures must parse fail-closed-clean.
        URLProtocolStub.handler = { _ in .init(status: 200, body: fixture("live-mimo-balance")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = MiMoAdapter(descriptor: account(), keychain: keys, http: stubbedHTTPClient())
        let primary = try await adapter.fetchPrimary(scope: .account).get()
        #expect(primary.balances?.count == 6)
        #expect(primary.balances?.allSatisfy { $0.currency == "USD" } == true)
    }

    @Test func liveEmptyUsageAndBillingListsAreValid() async throws {
        URLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/usage/daily") {
                return .init(status: 200, body: fixture("live-mimo-usage-daily"))
            }
            return .init(status: 200, body: fixture("live-mimo-billing-daily"))
        }
        defer { URLProtocolStub.handler = nil }
        let adapter = MiMoAdapter(descriptor: account(), keychain: keys, http: stubbedHTTPClient())
        let snapshot = try await adapter.fetchAccount()
        #expect(snapshot.usageHistory?.isEmpty == true)
        guard case .ok = snapshot.sections.first(where: { $0.kind == .usage })?.status else {
            Issue.record("expected usage .ok for empty live lists")
            return
        }
    }

    @Test func liveTokenPlanParsesStringPeriodAndIntCredits() async throws {
        URLProtocolStub.handler = { _ in .init(status: 200, body: fixture("live-mimo-token-plan")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = MiMoAdapter(descriptor: account(tp: true), keychain: keys, http: stubbedHTTPClient())
        let snapshot = try await adapter.fetchPrimary(scope: .quota(MiMoAdapter.quotaID)).get()
        #expect(snapshot.quota?.total == 11_000_000_000)
        #expect(snapshot.quota?.used == 2_018_653_495)
        #expect(snapshot.quota?.remaining == 8_981_346_505)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(snapshot.quota?.period?.start == calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 13, minute: 35, second: 26)))
        #expect(snapshot.quota?.period?.end == calendar.date(from: DateComponents(year: 2026, month: 12, day: 12, hour: 23, minute: 59, second: 59)))
    }

    @Test func billingCostIsAttachedToDay() async throws {
        stubRequests { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/usage/daily") {
                return .init(status: 200, body: fixture("mimo-usage-daily"))
            }
            if path.hasSuffix("/billing/daily") {
                return .init(status: 200, body: fixture("mimo-billing-daily"))
            }
            return .init(status: 200, body: fixture("mimo-list-empty"))
        }
        defer { URLProtocolStub.handler = nil }
        let adapter = MiMoAdapter(descriptor: account(), keychain: keys, http: stubbedHTTPClient())
        let snapshot = try await adapter.fetchAccount()
        guard let day = snapshot.usageHistory?.first else {
            Issue.record("expected usage history")
            return
        }
        #expect(day.localDay == "2026-11-11")
        #expect(day.timeZoneID == "UTC")
        #expect(day.requests == 3)
        #expect(day.tokensIn == 700)
        #expect(day.tokensOut == 300)
        #expect(day.cost == Money(role: .cash, amount: Decimal(string: "10.01")!, currency: "CNY"))
        #expect(day.models?.count == 1)
        #expect(day.models?.first?.model == "mimo-v2.6-pro")
        #expect(day.models?.first?.cost == Money(role: .cash, amount: Decimal(string: "0.012345")!, currency: "CNY"))
    }
}
}
