import Foundation
import Testing
@testable import TokenTankKit

struct KimiSlotMigrationTests {
    @Test func dropsSlotsWithoutReadableKey() {
        let account = testAccount(provider: .kimi, region: .cn, slots: [
            CredentialSlot(id: "sk", kind: .apiKey, keychainRef: "ref-sk", baseURLOverride: nil),
            CredentialSlot(id: "admin", kind: .admin, keychainRef: "ref-admin", baseURLOverride: nil),
        ])
        let keychain = InMemoryKeychain(storage: ["ref-sk": "sk-test"])
        let migrated = KimiSlotMigration.migrated(account, keychain: keychain)
        #expect(migrated?.credentialSlots.map(\.id) == ["sk"])
    }

    @Test func movesKimiCodeKeyToCodingSlot() {
        let id = UUID()
        let account = testAccount(id: id, provider: .kimi, region: .cn)
        let keychain = InMemoryKeychain(storage: ["ref-sk": "sk-kimi-abc"])
        let migrated = KimiSlotMigration.migrated(account, keychain: keychain)
        #expect(migrated?.credentialSlots.map(\.id) == ["coding"])
        #expect(migrated?.credentialSlots.first?.keychainRef == "\(id.uuidString)/coding")
        #expect(keychain.key(for: "\(id.uuidString)/coding") == "sk-kimi-abc")
        #expect(keychain.key(for: "ref-sk") == nil)
    }

    @Test func keepsAccountWhenNothingChanges() {
        let account = testAccount(provider: .kimi, region: .cn)
        let keychain = InMemoryKeychain(storage: ["ref-sk": "sk-test"])
        #expect(KimiSlotMigration.migrated(account, keychain: keychain) == nil)
    }

    @Test func keepsKeyInPlaceWhenCodingSlotExists() {
        let account = testAccount(provider: .kimi, region: .cn, slots: [
            CredentialSlot(id: "sk", kind: .apiKey, keychainRef: "ref-sk", baseURLOverride: nil),
            CredentialSlot(id: "coding", kind: .coding, keychainRef: "ref-coding", baseURLOverride: nil),
        ])
        let keychain = InMemoryKeychain(storage: ["ref-sk": "sk-kimi-abc", "ref-coding": "sk-kimi-xyz"])
        #expect(KimiSlotMigration.migrated(account, keychain: keychain) == nil)
        #expect(keychain.key(for: "ref-sk") == "sk-kimi-abc")
    }
}
