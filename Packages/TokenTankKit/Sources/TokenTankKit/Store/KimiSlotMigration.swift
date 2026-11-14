import Foundation

/// One-time migration of Kimi accounts saved by older builds: slots whose
/// Keychain item is unreadable are dropped, and a Kimi Code key (`sk-kimi-`) in
/// the `sk` slot moves to the `coding` slot.
public enum KimiSlotMigration {
    /// - Parameters:
    ///   - account: Kimi account to migrate.
    ///   - keychain: Keychain holding the slot secrets.
    /// - Returns: Descriptor with migrated slots, or `nil` when nothing changes.
    public static func migrated(_ account: AccountDescriptor, keychain: KeychainClient) -> AccountDescriptor? {
        let slots = account.credentialSlots
        let readable = slots.filter { keychain.key(for: $0.keychainRef) != nil }
        var migrated = readable
        let codingRef = "\(account.id.uuidString)/coding"
        if
            let legacy = readable.first(where: { $0.kind == .apiKey }),
            readable.contains(where: { $0.kind == .coding }) == false,
            let key = keychain.key(for: legacy.keychainRef),
            key.hasPrefix("sk-kimi-"),
            (try? keychain.set(key, for: codingRef)) != nil
        {
            try? keychain.remove(ref: legacy.keychainRef)
            migrated = readable.filter { $0.id != legacy.id } + [
                CredentialSlot(id: "coding", kind: .coding, keychainRef: codingRef, baseURLOverride: legacy.baseURLOverride),
            ]
        }
        var result: AccountDescriptor?
        if migrated.isEmpty == false, migrated.map(\.id) != slots.map(\.id) {
            var updated = account
            updated.credentialSlots = migrated
            result = updated
        }
        return result
    }
}
