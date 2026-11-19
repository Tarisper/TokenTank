import Foundation
import Testing
@testable import TokenTankKit

struct SnapshotStoreTests {
    private func makeSnapshot(accountID: UUID, balances: [Money]? = nil, sections: [SectionSnapshot]) -> AccountSnapshot {
        AccountSnapshot(
            accountID: accountID,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isAvailable: true,
            balances: balances,
            quotas: nil,
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: nil,
            sections: sections
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func writeThenReadRoundTrip() throws {
        let store = SnapshotStore(directory: try makeDirectory())
        let account = makeSnapshot(accountID: UUID(), sections: [
            SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: nil, lastAttemptAt: nil),
        ])
        try store.write(SnapshotFile(updatedAt: Date(), accounts: [account]))
        guard case .file(let file) = store.read() else {
            Issue.record("expected .file")
            return
        }
        #expect(file.version == SnapshotFile.currentVersion)
        #expect(file.accounts.count == 1)
        #expect(file.accounts.first?.accountID == account.accountID)
    }

    @Test func corruptFileIsUnreadable() throws {
        let directory = try makeDirectory()
        try Data("{not json".utf8).write(to: directory.appendingPathComponent("snapshot.json"))
        #expect({
            if case .unreadable = SnapshotStore(directory: directory).read() { return true }
            return false
        }())
    }

    @Test func unreadableFileIsBackedUpBeforeOverwrite() throws {
        let directory = try makeDirectory()
        try Data("{not json".utf8).write(to: directory.appendingPathComponent("snapshot.json"))
        let store = SnapshotStore(directory: directory)
        let accountID = UUID()
        try store.update(account: makeSnapshot(accountID: accountID, sections: []))
        guard case .file(let file) = store.read() else {
            Issue.record("expected .file after recovery")
            return
        }
        #expect(file.accounts.map(\.accountID) == [accountID])
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("snapshot.corrupt-") }
        #expect(backups.count == 1)
    }

    @Test func newerVersionIsNeverOverwritten() throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("snapshot.json")
        let json = #"{"version": 99, "updatedAt": 1000, "accounts": []}"#
        try Data(json.utf8).write(to: url)
        let store = SnapshotStore(directory: directory)
        try store.update(account: makeSnapshot(accountID: UUID(), sections: []))
        #expect(String(data: try Data(contentsOf: url), encoding: .utf8) == json)
        guard case .newerVersion = store.read() else {
            Issue.record("expected .newerVersion")
            return
        }
    }

    @Test func missingFileDegradesToEmpty() throws {
        let store = SnapshotStore(directory: try makeDirectory())
        #expect({
            if case .empty = store.read() { return true }
            return false
        }())
    }

    @Test func olderVersionIsMigrated() throws {
        let directory = try makeDirectory()
        let json = """
        {"version": 0, "updatedAt": 1000, "accounts": []}
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("snapshot.json"))
        guard case .file(let file) = SnapshotStore(directory: directory).read() else {
            Issue.record("expected .file after migration")
            return
        }
        #expect(file.version == SnapshotFile.currentVersion)
    }

    @Test func newerVersionIsNotInterpreted() throws {
        let directory = try makeDirectory()
        let json = """
        {"version": 99, "updatedAt": 1000, "accounts": []}
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("snapshot.json"))
        guard case .newerVersion(let version) = SnapshotStore(directory: directory).read() else {
            Issue.record("expected .newerVersion")
            return
        }
        #expect(version == 99)
    }

    @Test func mergeKeepsLastGoodDataOfFailedSections() {
        let accountID = UUID()
        let good = makeSnapshot(
            accountID: accountID,
            balances: [Money(role: .available, amount: 42, currency: "CNY")],
            sections: [SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: Date(timeIntervalSince1970: 1_000), lastAttemptAt: Date(timeIntervalSince1970: 1_000))]
        )
        let failed = AccountSnapshot(
            accountID: accountID,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isAvailable: nil,
            balances: nil,
            quotas: nil,
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: nil,
            sections: [SectionSnapshot(kind: .balance, slotID: "sk", status: .failed(.network(code: -1009)), lastSuccessAt: nil, lastAttemptAt: Date(timeIntervalSince1970: 2_000))]
        )
        let merged = good.merging(failed)
        #expect(merged.balances?.first?.amount == 42)
        #expect(merged.updatedAt == Date(timeIntervalSince1970: 1_000))
        guard case .failed(.network(code: -1009))? = merged.sections.first?.status else {
            Issue.record("expected failed status")
            return
        }
        #expect(merged.sections.first?.lastSuccessAt == Date(timeIntervalSince1970: 1_000))
        #expect(merged.sections.first?.lastAttemptAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test func mergeReplacesDataOfSuccessfulSections() {
        let accountID = UUID()
        let old = makeSnapshot(
            accountID: accountID,
            balances: [Money(role: .available, amount: 42, currency: "CNY")],
            sections: [SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: nil, lastAttemptAt: nil)]
        )
        let incoming = AccountSnapshot(
            accountID: accountID,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isAvailable: false,
            balances: [Money(role: .available, amount: 1, currency: "CNY")],
            quotas: nil,
            usageHistory: nil,
            balanceHistory: nil,
            limits: nil,
            modelTopByScope: nil,
            sections: [
                SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: Date(timeIntervalSince1970: 2_000), lastAttemptAt: Date(timeIntervalSince1970: 2_000)),
                SectionSnapshot(kind: .usage, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil),
            ]
        )
        let merged = old.merging(incoming)
        #expect(merged.balances?.first?.amount == 1)
        #expect(merged.isAvailable == false)
        #expect(merged.updatedAt == Date(timeIntervalSince1970: 2_000))
        #expect(merged.sections.count == 2)
    }

    @Test func mergeDropsErrorsFromReplacedSlotsAndPreservesOtherSections() {
        let accountID = UUID()
        let previous = makeSnapshot(accountID: accountID, sections: [
            SectionSnapshot(kind: .balance, slotID: "sk", status: .failed(.invalidKey), lastSuccessAt: nil, lastAttemptAt: nil),
            SectionSnapshot(kind: .usage, slotID: "admin", status: .failed(.invalidKey), lastSuccessAt: nil, lastAttemptAt: nil),
            SectionSnapshot(kind: .quotas, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil),
            SectionSnapshot(kind: .limits, slotID: nil, status: .ok, lastSuccessAt: nil, lastAttemptAt: nil),
        ])
        let incoming = makeSnapshot(accountID: accountID, sections: [
            SectionSnapshot(kind: .balance, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil),
            SectionSnapshot(kind: .usage, slotID: nil, status: .unsupported, lastSuccessAt: nil, lastAttemptAt: nil),
            SectionSnapshot(kind: .quotas, slotID: "coding", status: .ok, lastSuccessAt: nil, lastAttemptAt: nil),
        ])

        let merged = previous.merging(incoming)
        #expect(merged.sections.count == 4)
        #expect(merged.sections.map(\.slotID) == [nil, nil, "coding", nil])
        #expect(merged.sections.map(\.status) == [.unsupported, .unsupported, .ok, .ok])
    }

    @Test func updateMergesByAccountID() throws {
        let store = SnapshotStore(directory: try makeDirectory())
        let accountID = UUID()
        let first = makeSnapshot(
            accountID: accountID,
            balances: [Money(role: .available, amount: 7, currency: "CNY")],
            sections: [SectionSnapshot(kind: .balance, slotID: "sk", status: .ok, lastSuccessAt: nil, lastAttemptAt: nil)]
        )
        try store.update(account: first)
        try store.update(account: makeSnapshot(accountID: accountID, sections: [
            SectionSnapshot(kind: .balance, slotID: "sk", status: .failed(.server(status: 500)), lastSuccessAt: nil, lastAttemptAt: nil),
        ]))
        guard case .file(let file) = store.read() else {
            Issue.record("expected .file")
            return
        }
        #expect(file.accounts.count == 1)
        #expect(file.accounts.first?.balances?.first?.amount == 7)
    }

    @Test func concurrentUpdatesAcrossStoreInstancesPreserveEveryAccount() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stores = [SnapshotStore(directory: directory), SnapshotStore(directory: directory)]
        let snapshots = (0..<48).map { index in
            makeSnapshot(accountID: UUID(), balances: [Money(role: .available, amount: Decimal(index), currency: "CNY")], sections: [])
        }
        DispatchQueue.concurrentPerform(iterations: snapshots.count) { index in
            do {
                try stores[index % stores.count].update(account: snapshots[index])
            } catch {
                Issue.record(error)
            }
        }
        let file = try #require({
            if case .file(let file) = stores[0].read() { return file }
            return nil
        }())
        #expect(Set(file.accounts.map(\.accountID)) == Set(snapshots.map(\.accountID)))
        for snapshot in snapshots {
            #expect(file.accounts.first { $0.accountID == snapshot.accountID }?.balances == snapshot.balances)
        }
    }
}
