import Foundation

/// Result of one refresh attempt (§2.1).
public enum RefreshOutcome: Equatable, Sendable {
    /// The fetch ran and every attempted section succeeded (or is unsupported).
    case success
    /// Skipped: dedup window, pending backoff or deferred wait.
    case skipped
    /// Retryable failure — one-shot reschedule at the date
    /// (backoff ladder, `Retry-After` or the 07:00 UTC+8 deferral).
    case retryAt(Date)
    /// Permanent failure (`invalidKey`/`regionMismatch`/`decoding`) — no retry.
    case failed(ProviderError)
}

/// Polling engine (§2.1): per-account dedup, backoff state and event-driven
/// refresh. The `NSBackgroundActivityScheduler`/`NWPathMonitor`/wake wrappers
/// live in the app and call into this actor.
public actor FetchScheduler {
    /// Polling configuration.
    public struct Config: Sendable {
        /// Polling period; clamped to the 5-minute minimum.
        public var interval: TimeInterval
        /// Per-account dedup window for event-driven refreshes (§2.1).
        public var minimumInterval: TimeInterval

        /// - Parameters:
        ///   - interval: Polling period in seconds (≥ 5 min).
        ///   - minimumInterval: Dedup window in seconds (≥ 5 min).
        public init(interval: TimeInterval = 15 * 60, minimumInterval: TimeInterval = 5 * 60) {
            self.interval = max(interval, 5 * 60)
            self.minimumInterval = max(minimumInterval, 5 * 60)
        }

        /// Scheduler tolerance (jitter) — at least 30% of the interval (§2.1).
        public var tolerance: TimeInterval {
            interval * 0.3
        }
    }

    private struct AccountState {
        var attempt = 0
        var blockedUntil: Date?
        var backoffUntil: Date?
    }

    private let refresher: AccountRefresher
    private let clock: Clock
    private let config: Config
    private var states: [UUID: AccountState] = [:]
    private var inFlight: Set<UUID> = []

    /// - Parameters:
    ///   - refresher: Fetch → merge → store pipeline.
    ///   - clock: Injectable clock (§9.2).
    ///   - config: Polling configuration.
    public init(refresher: AccountRefresher, clock: Clock = SystemClock(), config: Config = Config()) {
        self.refresher = refresher
        self.clock = clock
        self.config = config
    }

    /// Runs one polling cycle over all accounts in order (one interval for all).
    /// - Parameters:
    ///   - accounts: Accounts to poll.
    ///   - force: Bypass the dedup window (scheduled cycle); backoff is still respected.
    /// - Returns: Per-account outcomes.
    @discardableResult
    public func runCycle(accounts: [AccountDescriptor], force: Bool = false) async -> [UUID: RefreshOutcome] {
        let ids = Set(accounts.map(\.id))
        states = states.filter { ids.contains($0.key) }
        var results: [UUID: RefreshOutcome] = [:]
        for account in accounts {
            results[account.id] = await refresh(account, force: force)
        }
        return results
    }

    /// Refreshes one account (poll tick or event: wake/network/manual/key saved).
    /// An account is never fetched more often than the minimum interval,
    /// even by events, and never twice at the same time.
    /// - Parameters:
    ///   - account: Account to refresh.
    ///   - force: Bypass the dedup/backoff block; used when a corrected key is saved.
    /// - Returns: Outcome of the attempt; `.skipped` while the same account is in flight.
    @discardableResult
    public func refresh(_ account: AccountDescriptor, force: Bool = false) async -> RefreshOutcome {
        guard inFlight.insert(account.id).inserted else {
            return .skipped
        }
        defer { inFlight.remove(account.id) }
        let now = clock.now
        var state = states[account.id] ?? AccountState()
        // Backoff always wins; force only bypasses the dedup window.
        if let backoffUntil = state.backoffUntil, now < backoffUntil {
            return .skipped
        }
        if force == false, let blockedUntil = state.blockedUntil, now < blockedUntil {
            return .skipped
        }
        let outcome = await attempt(account, state: &state)
        states[account.id] = state
        return outcome
    }

    private func attempt(_ account: AccountDescriptor, state: inout AccountState) async -> RefreshOutcome {
        let failure: (error: ProviderError, adminSource: Bool)
        do {
            let snapshot = try await refresher.refresh(account)
            guard
                case .failed(let error) = snapshot.sections.first(where: { section in
                    if case .failed = section.status { return true }
                    return false
                })?.status
            else {
                state.attempt = 0
                state.blockedUntil = clock.now.addingTimeInterval(config.minimumInterval)
                state.backoffUntil = nil
                return .success
            }
            let adminSource = snapshot.sections.contains { section in
                if case .failed = section.status { return section.slotID == "admin" }
                return false
            }
            failure = (error, adminSource)
        } catch let error as ProviderError {
            failure = (error, false)
        } catch {
            failure = (.network(code: URLError.Code.unknown.rawValue), false)
        }
        return resolve(failure: failure, state: &state)
    }

    private func resolve(failure: (error: ProviderError, adminSource: Bool), state: inout AccountState) -> RefreshOutcome {
        // Backoff is measured from the failure, not from the attempt start:
        // a 30 s timeout would otherwise consume the whole retry delay.
        let now = clock.now
        let outcome: RefreshOutcome
        switch failure.error {
        case .invalidKey, .regionMismatch, .decoding, .unsupported:
            state.attempt = 0
            state.blockedUntil = now.addingTimeInterval(config.minimumInterval)
            state.backoffUntil = nil
            outcome = .failed(failure.error)
        case .dataNotReady:
            let deadline = Self.nextDataReadyTime(after: now)
            state.attempt = 0
            state.blockedUntil = deadline
            state.backoffUntil = deadline
            outcome = .retryAt(deadline)
        case .rateLimited, .server, .network:
            let ladder = failure.adminSource ? BackoffLadder.kimiAdmin : .standard
            let retryAfterDelay = retryAfter(of: failure.error).flatMap { $0 > 0 ? $0 : nil }
            let delay = retryAfterDelay ?? ladder.delay(attempt: state.attempt + 1)
            state.attempt += 1
            let deadline = now.addingTimeInterval(delay)
            state.blockedUntil = deadline
            state.backoffUntil = deadline
            outcome = .retryAt(deadline)
        }
        return outcome
    }

    private func retryAfter(of error: ProviderError) -> TimeInterval? {
        if case .rateLimited(let retryAfter) = error {
            return retryAfter
        }
        return nil
    }

    /// Next 07:00 UTC+8 (T+1 readiness of the Kimi admin billing data).
    private static func nextDataReadyTime(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let deadline = calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 7, minute: 0),
            matchingPolicy: .nextTime
        )
        return deadline ?? date.addingTimeInterval(3600)
    }
}
