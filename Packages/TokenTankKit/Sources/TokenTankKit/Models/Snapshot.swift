import Foundation

/// Fetch outcome of one section.
public enum FetchStatus: Codable, Equatable {
    case ok
    /// The section did not update; last-good data is shown with an indicator.
    case failed(ProviderError)
    /// The provider does not expose this data (e.g. DeepSeek usage).
    case unsupported
}

/// Status of one section (or credential slot) of an account snapshot.
public struct SectionSnapshot: Codable {
    public let kind: SectionKind
    /// `sk`/`tp`/`admin`/`nil` — MiMo slots get independent statuses.
    public let slotID: String?
    public let status: FetchStatus
    /// Time of the last success — the age of the last-good data.
    public let lastSuccessAt: Date?
    /// Time of the last attempt (including failures).
    public let lastAttemptAt: Date?
}

/// Snapshot of a single account inside `SnapshotFile`.
public struct AccountSnapshot: Codable {
    public let accountID: UUID
    /// Last successful fetch of any section.
    public let updatedAt: Date
    /// «Can the account make calls» (deepseek/mimo).
    public let isAvailable: Bool?
    public let balances: [Money]?
    public let quotas: [Quota]?
    /// Accumulated history (storage policy §10).
    public let usageHistory: [DailyUsage]?
    /// 90 days, one series per currency (§3.5).
    public let balanceHistory: [BalancePoint]?
    public let limits: RateLimits?
    /// Key — `Scope.rawValue` (`"account"` | `"quota:<id>"`): a plain string is more
    /// stable than a dictionary with an enum key.
    public let modelTopByScope: [String: [ModelUsage]]?
    /// Status of each section/slot separately.
    public let sections: [SectionSnapshot]
}

/// Snapshot file stored in the App Group container.
public struct SnapshotFile: Codable {
    public static let currentVersion = 1

    public let version: Int
    /// Time of the last file change.
    public let updatedAt: Date
    public let accounts: [AccountSnapshot]

    public init(version: Int = SnapshotFile.currentVersion, updatedAt: Date, accounts: [AccountSnapshot]) {
        self.version = version
        self.updatedAt = updatedAt
        self.accounts = accounts
    }
}

extension AccountSnapshot {
    /// Merges an incoming fetch result into the receiver per the last-good policy:
    /// data of a section whose incoming status is not `.ok` is preserved, only the
    /// status record updates. `updatedAt` advances only when some section succeeded.
    /// - Parameter incoming: Fetch result to merge.
    /// - Returns: Merged snapshot.
    public func merging(_ incoming: AccountSnapshot) -> AccountSnapshot {
        var balances = self.balances
        var isAvailable = self.isAvailable
        var balanceHistory = self.balanceHistory
        var quotas = self.quotas
        var usageHistory = self.usageHistory
        var modelTopByScope = self.modelTopByScope
        var limits = self.limits

        for section in incoming.sections where section.status == .ok {
            switch section.kind {
            case .balance:
                balances = incoming.balances ?? balances
                isAvailable = incoming.isAvailable ?? isAvailable
                balanceHistory = incoming.balanceHistory ?? balanceHistory
            case .quotas:
                quotas = incoming.quotas ?? quotas
            case .usage:
                usageHistory = incoming.usageHistory ?? usageHistory
                modelTopByScope = incoming.modelTopByScope ?? modelTopByScope
            case .limits:
                limits = incoming.limits ?? limits
            }
        }

        var sections: [SectionSnapshot] = []
        for incomingSection in incoming.sections {
            let existing = self.sections.first {
                $0.kind == incomingSection.kind && $0.slotID == incomingSection.slotID
            }
            sections.append(SectionSnapshot(
                kind: incomingSection.kind,
                slotID: incomingSection.slotID,
                status: incomingSection.status,
                lastSuccessAt: incomingSection.lastSuccessAt ?? existing?.lastSuccessAt,
                lastAttemptAt: incomingSection.lastAttemptAt ?? existing?.lastAttemptAt
            ))
        }
        for existingSection in self.sections {
            let covered = incoming.sections.contains {
                $0.kind == existingSection.kind && $0.slotID == existingSection.slotID
            }
            if covered == false {
                sections.append(existingSection)
            }
        }

        let anySuccess = incoming.sections.contains { $0.status == .ok }
        return AccountSnapshot(
            accountID: accountID,
            updatedAt: anySuccess ? max(updatedAt, incoming.updatedAt) : updatedAt,
            isAvailable: isAvailable,
            balances: balances,
            quotas: quotas,
            usageHistory: usageHistory,
            balanceHistory: balanceHistory,
            limits: limits,
            modelTopByScope: modelTopByScope,
            sections: sections
        )
    }
}
