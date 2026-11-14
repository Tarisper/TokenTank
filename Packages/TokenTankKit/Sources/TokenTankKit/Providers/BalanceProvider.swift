import Foundation

/// A provider adapter bound to one account.
public protocol BalanceProvider {
    var descriptor: AccountDescriptor { get }

    /// Fetches all sections of the account snapshot (per-section statuses).
    /// - Returns: Snapshot with independent section statuses.
    func fetchAccount() async throws -> AccountSnapshot

    /// Fetches exactly one section for the widget extension (REQ-CFG-8).
    /// - Parameter scope: `.account`/`.sk` resolves to balance, `.quota(<tp>)` to the token plan.
    /// - Returns: Light snapshot; display-only — never written to `SnapshotStore`.
    ///   Render by the **returned** `scope` (e.g. a tp-only MiMo account resolves
    ///   `.account` to its first quota), not by the requested one. Credential-level
    ///   failures (`invalidKey`/`regionMismatch`) render as `error`, transient
    ///   ones as the refresh-failed indicator over last-good data.
    func fetchPrimary(scope: Scope) async -> Result<PrimarySnapshot, ProviderError>
}
