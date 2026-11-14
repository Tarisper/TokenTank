import Foundation
import Testing
@testable import TokenTankKit

struct AccountStoreTests {
    private func makeDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = "AccountStoreTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func saveThenReadRoundTrip() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AccountStore(defaults: defaults)
        let account = testAccount(provider: .kimi, region: .cn)
        try store.save(account)
        #expect(store.accounts().map(\.id) == [account.id])
    }

    @Test func saveUpsertsByAccountID() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AccountStore(defaults: defaults)
        let accountID = UUID()
        var account = testAccount(id: accountID, provider: .deepseek)
        try store.save(account)
        account.label = "renamed"
        try store.save(account)
        let accounts = store.accounts()
        #expect(accounts.count == 1)
        #expect(accounts.first?.label == "renamed")
    }

    @Test func deleteRemovesOnlyThatAccount() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AccountStore(defaults: defaults)
        let first = testAccount(provider: .deepseek)
        let second = testAccount(provider: .mimo)
        try store.save(first)
        try store.save(second)
        store.delete(id: first.id)
        #expect(store.accounts().map(\.id) == [second.id])
    }

    @Test func corruptedRecordDoesNotHideOtherAccounts() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AccountStore(defaults: defaults)
        let account = testAccount(provider: .deepseek)
        try store.save(account)
        guard let data = defaults.data(forKey: "tokentank.accounts") else {
            Issue.record("expected stored accounts")
            return
        }
        var records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        records.append(["id": "not-a-uuid", "provider": "deepseek"])
        defaults.set(try JSONSerialization.data(withJSONObject: records), forKey: "tokentank.accounts")
        #expect(store.accounts().map(\.id) == [account.id])
        // A following save keeps the healthy record instead of rewriting the file
        // with a single account.
        let second = testAccount(provider: .mimo)
        try store.save(second)
        #expect(store.accounts().map(\.id) == [account.id, second.id])
    }

    @Test func corruptedDataDegradesToEmpty() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("garbage".utf8), forKey: "tokentank.accounts")
        #expect(AccountStore(defaults: defaults).accounts().isEmpty)
    }
}
