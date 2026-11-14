import Foundation

/// Account settings in the shared `UserDefaults` suite (read-only from the widget
/// extension; the app is the single writer).
public struct AccountStore {
    private static let key = "tokentank.accounts"

    private let defaults: UserDefaults

    /// - Parameter defaults: Shared suite (`UserDefaults(suiteName:)` of the App Group).
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Returns stored accounts; corrupted records are skipped so one bad entry
    /// cannot hide the others.
    /// - Returns: Accounts ordered as saved.
    public func accounts() -> [AccountDescriptor] {
        guard let data = defaults.data(forKey: Self.key) else {
            return []
        }
        guard let records = try? JSONDecoder().decode([LossyRecord].self, from: data) else {
            return []
        }
        return records.compactMap(\.account)
    }

    /// Saves the account, replacing any existing account with the same `id`.
    /// - Parameter account: Account to upsert.
    /// - Throws: Encoding errors.
    public func save(_ account: AccountDescriptor) throws {
        var accounts = accounts()
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        defaults.set(try JSONEncoder().encode(accounts), forKey: Self.key)
    }

    /// Removes the account with the given id.
    /// - Parameter id: Account identifier.
    public func delete(id: UUID) {
        let accounts = accounts().filter { $0.id != id }
        defaults.set(try? JSONEncoder().encode(accounts), forKey: Self.key)
    }

    /// Element-wise decoding: a record that fails to decode becomes `nil`
    /// instead of failing the whole array.
    private struct LossyRecord: Decodable {
        let account: AccountDescriptor?

        init(from decoder: Decoder) throws {
            account = try? AccountDescriptor(from: decoder)
        }
    }
}
