import Foundation

/// Retention cleanup of accumulated histories (§10): keeps the newest records
/// and drops the oldest beyond the retention window. Runs on every successful
/// write (merge) and at app startup for stored snapshots.
public enum HistoryPolicy {
    /// Usage retention window for the given quotas (§10: `max(90, quota period)`).
    /// - Parameter quotas: Account quotas; the period extends the window.
    /// - Returns: Days to keep.
    public static func usageRetentionDays(quotas: [Quota]?) -> Int {
        let quotaDays = quotas?.compactMap { quota -> Int? in
            guard let period = quota.period else { return nil }
            return Int((period.end.timeIntervalSince(period.start) / 86_400).rounded(.up))
        }.max()
        return UsageHistory.retentionDays(quotaPeriodDays: quotaDays)
    }

    /// Trims the accumulated histories of a stored snapshot.
    /// - Parameter snapshot: Account snapshot.
    /// - Returns: Snapshot with histories trimmed to their retention windows.
    public static func cleanup(_ snapshot: AccountSnapshot) -> AccountSnapshot {
        AccountSnapshot(
            accountID: snapshot.accountID,
            updatedAt: snapshot.updatedAt,
            isAvailable: snapshot.isAvailable,
            balances: snapshot.balances,
            quotas: snapshot.quotas,
            usageHistory: UsageHistory.merging(
                existing: snapshot.usageHistory ?? [],
                incoming: [],
                retentionDays: usageRetentionDays(quotas: snapshot.quotas)
            ),
            balanceHistory: BalanceHistory.trimmed(snapshot.balanceHistory ?? []),
            limits: snapshot.limits,
            modelTopByScope: snapshot.modelTopByScope,
            sections: snapshot.sections
        )
    }
}
