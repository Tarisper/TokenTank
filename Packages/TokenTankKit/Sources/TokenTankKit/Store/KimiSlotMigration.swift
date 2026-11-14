import Foundation

/// Moves a legacy Kimi Code key (`sk-kimi-`) from `sk` to `coding`,
/// preserving slots whose Keychain items are temporarily unavailable.
public enum KimiSlotMigration {
    /// - Parameters:
    ///   - account: Kimi account to migrate.
    ///   - keychain: Keychain holding the slot secrets.
    /// - Returns: Descriptor with migrated slots, or `nil` when nothing changes.
    public static func migrated(_ account: AccountDescriptor, keychain: KeychainClient) -> AccountDescriptor? {
        let slots = account.credentialSlots
        var migrated = slots
        let codingRef = "\(account.id.uuidString)/coding"
        if
            let legacy = slots.first(where: { $0.kind == .apiKey }),
            slots.contains(where: { $0.kind == .coding }) == false,
            let key = keychain.key(for: legacy.keychainRef),
            key.hasPrefix("sk-kimi-"),
            (try? keychain.set(key, for: codingRef)) != nil
        {
            try? keychain.remove(ref: legacy.keychainRef)
            migrated = slots.filter { $0.id != legacy.id } + [
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
