import Foundation
import TokenTankKit
import TokenTankWidgetUI
import WidgetKit

/// Timeline entry carrying resolved states for all layouts.
struct WidgetEntry: TimelineEntry {
    let date: Date
    let accountID: UUID?
    let scope: Scope
    let layout: SmallLayoutOption
    let small: WidgetViewState.Small
    let medium: WidgetViewState.Medium
    let topModels: WidgetViewState.TopModels
    /// Update time of the underlying data (staleness-boundary entry).
    let dataUpdatedAt: Date?
    /// Active mode fetch failed — show «could not update» over last-good data.
    let activeFailed: Bool
}

/// Timeline provider: passive mode only reads the shared snapshot; the active
/// mode (opt-in, default off — REQ-CFG-4) performs one lightweight
/// `fetchPrimary` per entry batch and writes nothing (REQ-CFG-8).
struct WidgetTimelineProvider: AppIntentTimelineProvider {
    private static let reloadInterval: TimeInterval = 15 * 60

    /// Widget configuration resolved once per entry batch.
    private struct Selection {
        let account: AccountDescriptor?
        let snapshot: AccountSnapshot?
        let scope: Scope
        let layout: SmallLayoutOption
        let focusAccountID: UUID?
        let accounts: [AccountDescriptor]
        let snapshots: [UUID: AccountSnapshot]

        init(intent: TokenTankWidgetIntent?, state: (accounts: [AccountDescriptor], snapshots: [UUID: AccountSnapshot])) {
            accounts = state.accounts
            snapshots = state.snapshots
            let selected = intent?.account.flatMap { entity in state.accounts.first { $0.id == entity.id } }
            account = selected ?? state.accounts.first
            snapshot = account.flatMap { state.snapshots[$0.id] }
            scope = (intent?.scope ?? .account).resolved(quotaID: snapshot?.quotas?.first?.id)
            layout = intent?.layout ?? .ring
            focusAccountID = selected?.id
        }
    }

    func placeholder(in context: Context) -> WidgetEntry {
        let selection = Selection(intent: nil, state: loadStoredWidgetState())
        return makeEntry(selection: selection, primaryResult: nil, now: Date())
    }

    func snapshot(for intent: TokenTankWidgetIntent, in context: Context) async -> WidgetEntry {
        let selection = Selection(intent: intent, state: loadStoredWidgetState())
        let primary = await primaryResult(intent: intent, selection: selection)
        return makeEntry(selection: selection, primaryResult: primary, now: Date())
    }

    func timeline(for intent: TokenTankWidgetIntent, in context: Context) async -> Timeline<WidgetEntry> {
        let now = Date()
        let selection = Selection(intent: intent, state: loadStoredWidgetState())
        // One request for the whole timeline, reused by every entry.
        let primary = await primaryResult(intent: intent, selection: selection)
        var entries = [makeEntry(selection: selection, primaryResult: primary, now: now)]
        let next = now.addingTimeInterval(Self.reloadInterval)
        entries.append(makeEntry(selection: selection, primaryResult: primary, now: next))
        // A dedicated entry on the staleness boundary (§2).
        if let dataUpdatedAt = entries[0].dataUpdatedAt {
            let staleAt = dataUpdatedAt.addingTimeInterval(ViewStateBuilder.staleness)
            if staleAt > now, staleAt < next {
                entries.append(makeEntry(selection: selection, primaryResult: primary, now: staleAt))
            }
        }
        entries.sort { $0.date < $1.date }
        return Timeline(entries: entries, policy: .after(next))
    }

    /// Active-mode request; `nil` when the user did not opt in (REQ-CFG-4).
    private func primaryResult(
        intent: TokenTankWidgetIntent,
        selection: Selection
    ) async -> Result<PrimarySnapshot, ProviderError>? {
        var result: Result<PrimarySnapshot, ProviderError>?
        if intent.active == true, let account = selection.account {
            result = await fetchPrimary(account: account, scope: selection.scope)
        }
        return result
    }

    private func makeEntry(
        selection: Selection,
        primaryResult: Result<PrimarySnapshot, ProviderError>?,
        now: Date
    ) -> WidgetEntry {
        let effectiveAccount = selection.account ?? placeholderAccount
        var snapshots = selection.snapshots
        var primaryScope: Scope?
        let resolved: (state: WidgetViewState.Small, activeFailed: Bool)
        if let primaryResult {
            primaryScope = selection.scope
            if case .success(let primary) = primaryResult {
                primaryScope = primary.scope
            }
            snapshots[effectiveAccount.id] = AccountSnapshot(
                account: effectiveAccount,
                primaryResult: primaryResult,
                scope: selection.scope,
                previous: selection.snapshot,
                now: now
            )
            resolved = ViewStateBuilder.small(
                account: effectiveAccount,
                primaryResult: primaryResult,
                snapshot: selection.snapshot,
                now: now
            )
        } else {
            resolved = (ViewStateBuilder.small(account: effectiveAccount, snapshot: selection.snapshot, now: now), false)
        }
        return WidgetEntry(
            date: now,
            accountID: selection.account?.id,
            scope: selection.scope,
            layout: selection.layout,
            small: resolved.state,
            medium: ViewStateBuilder.medium(
                accounts: selection.accounts,
                snapshots: snapshots,
                focusAccountID: selection.focusAccountID,
                primaryScope: primaryScope,
                now: now
            ),
            topModels: ViewStateBuilder.topModels(
                account: effectiveAccount,
                snapshot: selection.snapshot,
                scope: selection.scope,
                now: now
            ),
            dataUpdatedAt: snapshots[effectiveAccount.id].flatMap { ViewStateBuilder.dataUpdatedAt(of: $0) },
            activeFailed: resolved.activeFailed
        )
    }

    /// One 3-second section request; nothing is written to the store.
    private func fetchPrimary(account: AccountDescriptor, scope: Scope) async -> Result<PrimarySnapshot, ProviderError> {
        let adapter = AdapterRegistry.makeAdapter(descriptor: account, keychain: SystemKeychain())
        return await withTimeout(seconds: 3) {
            await adapter.fetchPrimary(scope: scope)
        } ?? .failure(.network(code: URLError.Code.timedOut.rawValue))
    }

    private var placeholderAccount: AccountDescriptor {
        AccountDescriptor(
            id: UUID(),
            provider: .deepseek,
            region: nil,
            label: "TokenTank",
            credentialSlots: [],
            tier: nil,
            thresholds: [],
            budgets: [],
            displayCurrency: nil
        )
    }
}

/// Stored accounts and their snapshots, as seen by the widget process.
func loadStoredWidgetState() -> (accounts: [AccountDescriptor], snapshots: [UUID: AccountSnapshot]) {
    let defaults = AppGroup.identifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    let accounts = AccountStore(defaults: defaults).accounts()
    let store = SnapshotStore(directory: AppGroup.containerURL() ?? FileManager.default.temporaryDirectory)
    var snapshots: [UUID: AccountSnapshot] = [:]
    if case .file(let file) = store.read() {
        for snapshot in file.accounts {
            snapshots[snapshot.accountID] = snapshot
        }
    }
    return (accounts, snapshots)
}

/// Runs an async operation with a deadline; `nil` when it does not finish in
/// time. The operation is cancelled when the deadline expires.
private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { try? await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next()
        group.cancelAll()
        return first ?? nil
    }
}
