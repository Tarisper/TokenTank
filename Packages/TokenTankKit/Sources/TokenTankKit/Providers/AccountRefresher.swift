import Foundation

/// Runs a full account fetch and persists the merge result — the shared
/// end-to-end path of the manual Refresh and (later) the background scheduler.
public struct AccountRefresher {
    private let keychain: KeychainClient
    private let store: SnapshotStore
    private let http: HTTPClient

    /// - Parameters:
    ///   - keychain: Source of slot keys.
    ///   - store: Snapshot store to update.
    ///   - http: HTTP client.
    public init(keychain: KeychainClient, store: SnapshotStore, http: HTTPClient = HTTPClient()) {
        self.keychain = keychain
        self.store = store
        self.http = http
    }

    /// Fetches all sections of the account and stores the last-good merge.
    /// Holds a background activity token exactly for the duration of the fetch (§2.1).
    /// On successful sections the accumulated histories are updated (§3.5):
    /// balance points are appended per currency, usage is deduplicated by
    /// `localDay` and trimmed to retention, and the top models are aggregated.
    /// - Parameter descriptor: Account to refresh.
    /// - Returns: The fetched snapshot (per-section statuses).
    /// - Throws: `ProviderError` on transport-level failures.
    public func refresh(_ descriptor: AccountDescriptor) async throws -> AccountSnapshot {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.background],
            reason: "tokentank.fetch"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }
        let adapter = AdapterRegistry.makeAdapter(descriptor: descriptor, keychain: keychain, http: http)
        let fetched = try await adapter.fetchAccount()
        let snapshot = enrich(fetched, previous: storedSnapshot(id: descriptor.id), timeZoneID: AdapterRegistry.dayTimeZone(for: descriptor.provider))
        try store.update(account: snapshot)
        return snapshot
    }

    private func storedSnapshot(id: UUID) -> AccountSnapshot? {
        if case .file(let file) = store.read() {
            return file.accounts.first { $0.accountID == id }
        }
        return nil
    }

    /// Updates accumulated histories from successful sections only (§10:
    /// last-good data of failed fetches is not re-evaluated).
    private func enrich(_ fetched: AccountSnapshot, previous: AccountSnapshot?, timeZoneID: String) -> AccountSnapshot {
        var balanceHistory = fetched.balanceHistory
        var usageHistory = fetched.usageHistory
        var modelTopByScope = fetched.modelTopByScope

        let balanceOK = fetched.sections.contains { $0.kind == .balance && $0.status == .ok }
        if balanceOK, let balances = fetched.balances {
            balanceHistory = BalanceHistory.appending(
                history: previous?.balanceHistory ?? [],
                balances: balances,
                at: Date(),
                timeZoneID: timeZoneID
            )
        }
        let usageOK = fetched.sections.contains { $0.kind == .usage && $0.status == .ok }
        if usageOK, let incoming = fetched.usageHistory {
            usageHistory = UsageHistory.merging(
                existing: previous?.usageHistory ?? [],
                incoming: incoming,
                retentionDays: HistoryPolicy.usageRetentionDays(quotas: fetched.quotas ?? previous?.quotas)
            )
            let history = usageHistory ?? []
            let now = Date()
            // Periods (REQ-TOP-5): `.account` — rolling 30 days, `.quota` —
            // the quota period (reset happens naturally when it changes).
            var tops: [String: [ModelUsage]] = [:]
            tops[Scope.account.rawValue] = TopModels.aggregate(
                history: history,
                fromDay: DayKey.string(for: now.addingTimeInterval(-30 * 86_400), timeZoneID: timeZoneID),
                toDay: DayKey.string(for: now, timeZoneID: timeZoneID)
            )
            for quota in fetched.quotas ?? previous?.quotas ?? [] {
                guard let period = quota.period else { continue }
                tops[Scope.quota(quota.id).rawValue] = TopModels.aggregate(
                    history: history,
                    fromDay: DayKey.string(for: period.start, timeZoneID: timeZoneID),
                    toDay: DayKey.string(for: period.end, timeZoneID: timeZoneID)
                )
            }
            modelTopByScope = tops
        }

        return AccountSnapshot(
            accountID: fetched.accountID,
            updatedAt: fetched.updatedAt,
            isAvailable: fetched.isAvailable,
            balances: fetched.balances,
            quotas: fetched.quotas,
            usageHistory: usageHistory,
            balanceHistory: balanceHistory,
            limits: fetched.limits,
            modelTopByScope: modelTopByScope,
            sections: fetched.sections
        )
    }
}
