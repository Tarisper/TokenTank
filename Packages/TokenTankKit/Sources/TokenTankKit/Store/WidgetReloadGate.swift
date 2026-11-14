import Foundation

/// Change-gated widget reload policy (§2): reload only when the semantic
/// content of the snapshot changed, at most once per `minimumInterval`.
/// Volatile fields (`updatedAt`, section attempt/success timestamps) do not
/// count as content changes.
public struct WidgetReloadGate: Sendable {
    private let minimumInterval: TimeInterval
    private var lastDigest: Data?
    private var lastReload: Date?
    private var pending = false

    /// - Parameter minimumInterval: Minimal gap between reloads (5 min per §2).
    public init(minimumInterval: TimeInterval = 5 * 60) {
        self.minimumInterval = minimumInterval
    }

    /// Records the snapshot content and decides whether to reload now.
    /// A change inside the reload window is remembered and fires on the next
    /// call after the window (nothing is swallowed).
    /// - Parameters:
    ///   - file: Current snapshot file.
    ///   - now: Current time.
    /// - Returns: `true` when widget timelines should be reloaded.
    public mutating func shouldReload(file: SnapshotFile, now: Date) -> Bool {
        let digest = Self.semanticDigest(of: file)
        if digest != lastDigest {
            lastDigest = digest
            pending = true
        }
        guard pending else { return false }
        if let lastReload, now.timeIntervalSince(lastReload) < minimumInterval {
            return false
        }
        pending = false
        lastReload = now
        return true
    }

    /// Digest of the meaningful content: statuses and data, not timestamps.
    private static func semanticDigest(of file: SnapshotFile) -> Data {
        let stable = SnapshotFile(
            version: file.version,
            updatedAt: Date(timeIntervalSince1970: 0),
            accounts: file.accounts.map { account in
                AccountSnapshot(
                    accountID: account.accountID,
                    updatedAt: Date(timeIntervalSince1970: 0),
                    isAvailable: account.isAvailable,
                    balances: account.balances,
                    quotas: account.quotas,
                    usageHistory: account.usageHistory,
                    balanceHistory: account.balanceHistory,
                    limits: account.limits,
                    modelTopByScope: account.modelTopByScope,
                    sections: account.sections.map {
                        SectionSnapshot(kind: $0.kind, slotID: $0.slotID, status: $0.status, lastSuccessAt: nil, lastAttemptAt: nil)
                    }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(stable)) ?? Data()
    }
}
