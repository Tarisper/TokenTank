import Foundation
import Testing
@testable import TokenTankKit

extension NetworkTests {
    struct AccountRefresherTests {
        @Test func refreshFetchesAndPersistsMergeResult() async throws {
            stubRequests { _ in .init(status: 200, body: fixture("deepseek-balance")) }
            defer { URLProtocolStub.handler = nil }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AccountRefresherTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = SnapshotStore(directory: directory)
            let refresher = AccountRefresher(
                keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]),
                store: store,
                http: stubbedHTTPClient()
            )
            let account = testAccount(provider: .deepseek)
            let snapshot = try await refresher.refresh(account)
            #expect(snapshot.balances?.isEmpty == false)
            guard case .file(let file) = store.read() else {
                Issue.record("expected persisted snapshot")
                return
            }
            #expect(file.accounts.first?.accountID == account.id)
        }

        @Test func mimoRefreshOnlyRefetchesRecentDaysAfterSuccessAndRateLimit() async throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AccountRefresherTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            defer { URLProtocolStub.handler = nil }
            let store = SnapshotStore(directory: directory)
            let refresher = AccountRefresher(
                keychain: InMemoryKeychain(storage: ["ref-sk": "sk-test"]),
                store: store,
                http: stubbedHTTPClient()
            )
            let account = testAccount(provider: .mimo)
            let olderDay = DayKey.string(for: Date().addingTimeInterval(-7 * 86_400), timeZoneID: "UTC")
            let olderUsage = Data(String(decoding: fixture("mimo-usage-daily"), as: UTF8.self)
                .replacingOccurrences(of: "2026-11-11", with: olderDay).utf8)
            stubRequests { request in
                let body: Data
                switch request.url?.lastPathComponent {
                case "balance": body = fixture("mimo-balance")
                case "daily" where request.url?.path.contains("/usage/") == true: body = olderUsage
                default: body = fixture("mimo-list-empty")
                }
                return .init(status: 200, body: body)
            }
            let initial = try await refresher.refresh(account)
            #expect(URLProtocolStub.requests.count == 7)

            stubRequests { request in
                request.url?.path.hasSuffix("/balance") == true
                    ? .init(status: 200, body: fixture("mimo-balance"))
                    : .init(status: 429, body: Data())
            }
            let limited = try await refresher.refresh(account)
            #expect(limited.sections.first { $0.kind == .usage }?.status == .failed(.rateLimited(retryAfter: nil)))
            #expect(URLProtocolStub.requests.count == 2)

            stubRequests { request in
                let body = request.url?.path.hasSuffix("/balance") == true
                    ? fixture("mimo-balance") : fixture("mimo-list-empty")
                return .init(status: 200, body: body)
            }
            let recovered = try await refresher.refresh(account)
            #expect(recovered.sections.first { $0.kind == .usage }?.status == .ok)
            #expect(recovered.usageHistory?.map(\.localDay) == [olderDay])
            #expect(URLProtocolStub.requests.count == 3)
            let expectedStart = DayKey.string(for: initial.updatedAt.addingTimeInterval(-86_400), timeZoneID: "UTC")
            for request in URLProtocolStub.requests where request.url?.path.hasSuffix("/balance") == false {
                let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
                #expect(query?.first { $0.name == "start_date" }?.value == expectedStart)
            }
        }

        @Test func validateKeyAcceptsSuccessfulModelsEndpoint() async throws {
            stubRequests { _ in .init(status: 200, body: Data(#"{"data": []}"#.utf8)) }
            defer { URLProtocolStub.handler = nil }
            let slot = CredentialSlot(id: "sk", kind: .apiKey, keychainRef: "ref-sk", baseURLOverride: nil)
            try await AdapterRegistry.validateKey(
                "sk-test",
                slot: slot,
                provider: .deepseek,
                region: nil,
                http: stubbedHTTPClient()
            )
        }

        @Test func validateKeyRejectsUnauthorized() async throws {
            stubRequests { _ in .init(status: 401, body: fixture("error-generic")) }
            defer { URLProtocolStub.handler = nil }
            let slot = CredentialSlot(id: "sk", kind: .apiKey, keychainRef: "ref-sk", baseURLOverride: nil)
            await #expect(throws: ProviderError.invalidKey) {
                try await AdapterRegistry.validateKey(
                    "sk-bad",
                    slot: slot,
                    provider: .deepseek,
                    region: nil,
                    http: stubbedHTTPClient()
                )
            }
        }

        @Test func validateTokenPlanSlotUsesOverrideBaseURL() async throws {
            stubRequests { request in
                #expect(request.url?.host == "token-plan-sgp.xiaomimimo.com")
                return .init(status: 200, body: Data(#"{"quota": {}}"#.utf8))
            }
            defer { URLProtocolStub.handler = nil }
            let slot = CredentialSlot(
                id: "tp",
                kind: .tokenPlan,
                keychainRef: "ref-tp",
                baseURLOverride: URL(string: "https://token-plan-sgp.xiaomimimo.com")
            )
            try await AdapterRegistry.validateKey(
                "tp-test",
                slot: slot,
                provider: .mimo,
                region: nil,
                http: stubbedHTTPClient()
            )
        }

        @Test(arguments: [KeyKind.coding, .tokenPlan])
        func customGatewayRequiresConfirmation(kind: KeyKind) async throws {
            stubRequests { _ in .init(status: 200, body: Data()) }
            defer { URLProtocolStub.handler = nil }
            let provider: ProviderID = kind == .coding ? .kimi : .mimo
            let slot = CredentialSlot(id: "custom", kind: kind, keychainRef: "ref", baseURLOverride: URL(string: "https://gateway.example"))
            await #expect(throws: ProviderError.unsupported) {
                try await AdapterRegistry.validateKey("test-key", slot: slot, provider: provider, region: .cn, http: stubbedHTTPClient())
            }
            #expect(URLProtocolStub.requests.isEmpty)
            try await AdapterRegistry.validateKey(
                "test-key", slot: slot, provider: provider, region: .cn,
                customGatewayConfirmed: true, http: stubbedHTTPClient()
            )
            #expect(URLProtocolStub.requests.count == 1)
            #expect(URLProtocolStub.requests.first?.url?.host == "gateway.example")
        }

        @Test func confirmationDoesNotAllowInsecureGateway() async throws {
            stubRequests { _ in .init(status: 200, body: Data()) }
            defer { URLProtocolStub.handler = nil }
            let slot = CredentialSlot(id: "tp", kind: .tokenPlan, keychainRef: "ref", baseURLOverride: URL(string: "http://gateway.example"))
            await #expect(throws: ProviderError.unsupported) {
                try await AdapterRegistry.validateKey(
                    "test-key", slot: slot, provider: .mimo, region: nil,
                    customGatewayConfirmed: true, http: stubbedHTTPClient()
                )
            }
            #expect(URLProtocolStub.requests.isEmpty)
        }
    }
}
