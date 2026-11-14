import Foundation
import Testing
@testable import TokenTankKit

extension NetworkTests {
struct DeepSeekAdapterTests {
    @Test func parsesMultiCurrencyBalance() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("deepseek-balance")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = DeepSeekAdapter(
            descriptor: testAccount(provider: .deepseek),
            keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]),
            http: stubbedHTTPClient()
        )
        let snapshot = try await adapter.fetchPrimary(scope: .account).get()
        #expect(snapshot.balances?.count == 6)
        #expect(snapshot.balances?.first == Money(role: .available, amount: Decimal(string: "15.50")!, currency: "CNY"))
        #expect(snapshot.balances?.contains(where: { $0.role == .available && $0.currency == "USD" }) == true)
        #expect(snapshot.balances?.contains(where: { $0.role == .granted && $0.amount == Decimal(string: "2.25")! }) == true)
        #expect(snapshot.balances?.contains(where: { $0.role == .toppedUp && $0.amount == Decimal(string: "5.50")! }) == true)
    }

    @Test func tolerantDecodingAcceptsNumbersNullsAndExtraFields() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("deepseek-balance-tolerant")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = DeepSeekAdapter(
            descriptor: testAccount(provider: .deepseek),
            keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]),
            http: stubbedHTTPClient()
        )
        let snapshot = try await adapter.fetchPrimary(scope: .account).get()
        #expect(snapshot.balances?.count == 2)
        #expect(snapshot.balances?.contains(where: { $0.role == .available && $0.amount == Decimal(15.5) }) == true)
        #expect(snapshot.balances?.contains(where: { $0.role == .granted }) == false)
    }

    @Test func liveBalanceIsMultiCurrency() async throws {
        // §9.4 probe (13.11.2026): `balance_infos` at multiple currencies is an
        // array of per-currency records with string amounts — the last open
        // [ПРОВЕРИТЬ] of §1, captured live (USD + CNY in one response).
        URLProtocolStub.handler = { _ in .init(status: 200, body: fixture("live-deepseek-balance")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = DeepSeekAdapter(
            descriptor: testAccount(provider: .deepseek),
            keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]),
            http: stubbedHTTPClient()
        )
        let snapshot = try await adapter.fetchPrimary(scope: .account).get()
        #expect(snapshot.balances?.count == 6)
        #expect(Set(snapshot.balances?.map(\.currency) ?? []) == ["USD", "CNY"])
        #expect(snapshot.balances?.contains { $0.role == .available && $0.currency == "CNY" && $0.amount == Decimal(string: "16.28")! } == true)
    }

    @Test func fetchAccountMarksUnsupportedSections() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("deepseek-balance")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = DeepSeekAdapter(
            descriptor: testAccount(provider: .deepseek),
            keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]),
            http: stubbedHTTPClient()
        )
        let snapshot = try await adapter.fetchAccount()
        #expect(snapshot.isAvailable == true)
        #expect(snapshot.sections.count == 4)
        guard case .ok = snapshot.sections.first(where: { $0.kind == .balance })?.status else {
            Issue.record("expected balance .ok")
            return
        }
        for kind in [SectionKind.quotas, .usage, .limits] {
            guard case .unsupported = snapshot.sections.first(where: { $0.kind == kind })?.status else {
                Issue.record("expected \(kind) .unsupported")
                return
            }
        }
    }

    @Test func quotaScopeIsUnsupported() async throws {
        let adapter = DeepSeekAdapter(
            descriptor: testAccount(provider: .deepseek),
            keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]),
            http: stubbedHTTPClient()
        )
        let result = await adapter.fetchPrimary(scope: .quota("q"))
        #expect(result == .failure(.unsupported))
    }

    @Test func missingKeyMapsToInvalidKey() async throws {
        stubRequests { _ in .init(status: 200, body: fixture("deepseek-balance")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = DeepSeekAdapter(
            descriptor: testAccount(provider: .deepseek),
            keychain: InMemoryKeychain(),
            http: stubbedHTTPClient()
        )
        await #expect(throws: ProviderError.invalidKey) {
            _ = try await adapter.fetchPrimary(scope: .account).get()
        }
    }

    @Test func unauthorizedResponseMapsToInvalidKey() async throws {
        stubRequests { _ in .init(status: 401, body: fixture("error-generic")) }
        defer { URLProtocolStub.handler = nil }
        let adapter = DeepSeekAdapter(
            descriptor: testAccount(provider: .deepseek),
            keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]),
            http: stubbedHTTPClient()
        )
        await #expect(throws: ProviderError.invalidKey) {
            _ = try await adapter.fetchPrimary(scope: .account).get()
        }
    }
}
}
