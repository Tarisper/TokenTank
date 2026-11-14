import Foundation
import SwiftUI
import TokenTankKit

/// App-side glue: account CRUD, manual refresh and key validation on top of
/// `TokenTankKit` services; contains no logic of its own. Background polling,
/// events and backoff are wired to `FetchScheduler` through `SchedulerHost`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [AccountDescriptor]
    @Published private(set) var snapshots: [UUID: AccountSnapshot] = [:]
    @Published private(set) var refreshing: Set<UUID> = []
    @Published private(set) var failedRefreshes: Set<UUID> = []
    @Published var route: AppRoute?

    let keychain = SystemKeychain()
    private let notifications = NotificationService()
    private var evaluators: [UUID: ThresholdEvaluator] = [:]
    private let accountStore: AccountStore
    private let thresholdState: ThresholdStateStore
    private let store: SnapshotStore
    private let scheduler: FetchScheduler
    private let schedulerHost: SchedulerHost

    init() {
        let container = AppGroup.containerURL()
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("TokenTank")
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let defaults = AppGroup.identifier.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        accountStore = AccountStore(defaults: defaults)
        thresholdState = ThresholdStateStore(defaults: .standard)
        store = SnapshotStore(directory: container)
        scheduler = FetchScheduler(refresher: AccountRefresher(keychain: keychain, store: store))
        schedulerHost = SchedulerHost(
            config: FetchScheduler.Config(
                interval: TimeInterval(RefreshSettings.minutes * 60),
                minimumInterval: 5 * 60
            ),
            store: store
        )
        accounts = accountStore.accounts()
        migrateKimiSlots()
        if case .file(let file) = store.read() {
            // Startup retention cleanup (§10): drop the oldest records first.
            let cleaned = file.accounts.map { HistoryPolicy.cleanup($0) }
            try? store.write(SnapshotFile(updatedAt: file.updatedAt, accounts: cleaned))
            for snapshot in cleaned {
                snapshots[snapshot.accountID] = snapshot
            }
        }
        schedulerHost.onPoll = { [weak self] in
            await self?.pollCycle()
        }
        schedulerHost.onEvent = { [weak self] in
            await self?.refreshAll()
        }
        schedulerHost.start()
        schedulerHost.reloadWidgetsIfChanged()
        notifications.requestAuthorization()
    }

    /// One-time fix-up of Kimi accounts saved by older builds (`KimiSlotMigration`).
    private func migrateKimiSlots() {
        for account in accounts where account.provider == .kimi {
            guard let migrated = KimiSlotMigration.migrated(account, keychain: keychain) else { continue }
            try? accountStore.save(migrated)
        }
        accounts = accountStore.accounts()
    }

    /// Persists the account settings (upsert by `id`) and refreshes it —
    /// saving a key is an instant-refresh event (§2.1), dedup applies.
    func save(_ account: AccountDescriptor) throws {
        try accountStore.save(account)
        accounts = accountStore.accounts()
        Task { await refresh(account, force: true) }
    }

    /// Removes the account and its Keychain items.
    func delete(_ account: AccountDescriptor) {
        for slot in account.credentialSlots {
            try? keychain.remove(ref: slot.keychainRef)
        }
        accountStore.delete(id: account.id)
        thresholdState.setTriggered([], for: account.id)
        snapshots[account.id] = nil
        accounts = accountStore.accounts()
    }

    /// Manual refresh of one account (event — dedup applies unless forced).
    func refresh(_ account: AccountDescriptor, force: Bool = false) async {
        let startedAt = Date()
        refreshing.insert(account.id)
        let outcome = await scheduler.refresh(account, force: force)
        refreshing.remove(account.id)
        reloadSnapshots()
        apply(outcome: outcome, for: account.id, attemptedAfter: startedAt)
        schedulerHost.reloadWidgetsIfChanged()
    }

    /// Manual refresh of all accounts (event — dedup applies).
    func refreshAll() async {
        let startedAt = Date()
        refreshing = Set(accounts.map(\.id))
        let outcomes = await scheduler.runCycle(accounts: accounts)
        refreshing = []
        reloadSnapshots()
        for (id, outcome) in outcomes {
            apply(outcome: outcome, for: id, attemptedAfter: startedAt)
        }
        schedulerHost.reloadWidgetsIfChanged()
    }

    /// Validates a key via the provider's validation endpoint.
    func validateKey(_ key: String, slot: CredentialSlot, account: AccountDescriptor, customGatewayConfirmed: Bool) async -> Result<Void, ProviderError> {
        do {
            try await AdapterRegistry.validateKey(
                key,
                slot: slot,
                provider: account.provider,
                region: account.region,
                customGatewayConfirmed: customGatewayConfirmed,
                http: HTTPClient()
            )
            return .success(())
        } catch let error as ProviderError {
            return .failure(error)
        } catch {
            return .failure(.network(code: -1))
        }
    }

    /// Persists the polling interval and reschedules the background poller.
    func setRefreshInterval(minutes: Int) {
        RefreshSettings.minutes = minutes
        schedulerHost.updateInterval(minutes: minutes)
    }

    private func pollCycle() async {
        let startedAt = Date()
        let outcomes = await scheduler.runCycle(accounts: accounts, force: true)
        reloadSnapshots()
        for (id, outcome) in outcomes {
            apply(outcome: outcome, for: id, attemptedAfter: startedAt)
        }
        schedulerHost.reloadWidgetsIfChanged()
    }

    private func apply(outcome: RefreshOutcome, for accountID: UUID, attemptedAfter: Date) {
        switch outcome {
        case .success:
            failedRefreshes.remove(accountID)
        case .skipped:
            break
        case .retryAt(let deadline):
            failedRefreshes.insert(accountID)
            schedulerHost.scheduleOneShot(at: deadline)
        case .failed:
            failedRefreshes.insert(accountID)
        }
        if outcome != .skipped {
            evaluateThresholds(accountID: accountID, attemptedAfter: attemptedAfter)
        }
    }

    private func reloadSnapshots() {
        if case .file(let file) = store.read() {
            for snapshot in file.accounts {
                snapshots[snapshot.accountID] = snapshot
            }
        }
    }

    /// The evaluator only advances thresholds of successfully fetched sections.
    private func evaluateThresholds(accountID: UUID, attemptedAfter: Date) {
        guard
            let account = accounts.first(where: { $0.id == accountID }),
            let snapshot = snapshots[accountID]
        else {
            return
        }
        var evaluator = evaluators[accountID]
            ?? ThresholdEvaluator(triggered: thresholdState.triggered(for: accountID))
        let triggers = evaluator.update(snapshot: snapshot, thresholds: account.thresholds, attemptedAfter: attemptedAfter)
        evaluators[accountID] = evaluator
        thresholdState.setTriggered(evaluator.triggered, for: accountID)
        for trigger in triggers {
            notifications.post(trigger, accountLabel: account.label)
        }
    }
}
