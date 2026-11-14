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
    }
}
