import Foundation
import Security

/// Errors thrown by `SystemKeychain` writes.
public enum KeychainError: Error {
    /// Underlying `SecItem` status.
    case status(OSStatus)
}

/// Keychain access identity shared by the app and the widget extension.
public enum KeychainAccess {
    /// Access group from the host Info.plist (`KeychainAccessGroup`), expanded at
    /// build time from `$(AppIdentifierPrefix)com.tokentank.shared`.
    public static var group: String? {
        Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
    }
}

/// `KeychainClient` backed by the shared Keychain access group. Items use
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and `synchronizable = false`
/// (§10); secrets never leave the Keychain.
public struct SystemKeychain: KeychainClient {
    private let service: String
    private let accessGroup: String?

    /// - Parameters:
    ///   - service: Keychain service name (namespace of `keychainRef`s).
    ///   - accessGroup: Access group; defaults to `KeychainAccess.group`.
    public init(service: String = "com.tokentank.shared", accessGroup: String? = KeychainAccess.group) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func key(for ref: String) -> String? {
        var query = baseQuery(ref: ref)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores the secret under the reference, updating an existing item in place:
    /// a failed write never deletes the previous key.
    /// - Parameters:
    ///   - key: Secret value.
    ///   - ref: `CredentialSlot.keychainRef`.
    /// - Throws: `KeychainError` when the item cannot be stored.
    public func set(_ key: String, for ref: String) throws {
        let data = Data(key.utf8)
        var query = baseQuery(ref: ref)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.status(updateStatus)
        }
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw KeychainError.status(addStatus)
        }
    }

    /// Deletes the stored secret; a missing item is not an error.
    /// - Parameter ref: `CredentialSlot.keychainRef`.
    /// - Throws: `KeychainError` on failures other than «not found».
    public func remove(ref: String) throws {
        let status = SecItemDelete(baseQuery(ref: ref) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.status(status)
        }
    }

    private func baseQuery(ref: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
