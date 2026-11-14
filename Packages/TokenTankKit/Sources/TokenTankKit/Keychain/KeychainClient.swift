import Foundation

/// Keychain seam: adapters only read secrets; account migration also writes them.
public protocol KeychainClient {
    /// Returns the secret stored under the reference, or `nil` when missing/unavailable.
    func key(for ref: String) -> String?

    /// Stores the secret under the reference, replacing an existing item.
    /// - Parameters:
    ///   - key: Secret value.
    ///   - ref: Reference to store the secret under.
    /// - Throws: An implementation-defined error when the item cannot be stored.
    func set(_ key: String, for ref: String) throws

    /// Deletes the secret stored under the reference; a missing item is not an error.
    /// - Parameter ref: Reference to delete.
    /// - Throws: An implementation-defined error on failure.
    func remove(ref: String) throws
}

/// In-memory `KeychainClient` for tests and previews.
public final class InMemoryKeychain: KeychainClient {
    private var storage: [String: String]

    /// - Parameter storage: Initial reference → secret mapping.
    public init(storage: [String: String] = [:]) {
        self.storage = storage
    }

    public func key(for ref: String) -> String? {
        storage[ref]
    }

    /// Stores the secret, replacing any existing value.
    public func set(_ key: String, for ref: String) {
        storage[ref] = key
    }

    /// Deletes the stored secret.
    public func remove(ref: String) {
        storage[ref] = nil
    }
}
