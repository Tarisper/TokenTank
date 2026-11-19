import AppKit
import Foundation
import Network
import TokenTankKit
import WidgetKit

/// System-side wrappers over the `FetchScheduler` engine (§2.1):
/// `NSBackgroundActivityScheduler` polling, wake/network events, one-shot
/// backoff reschedules and change-gated widget reloads. All scheduling logic
/// lives in `FetchScheduler`; this type only binds system APIs to it.
@MainActor
final class SchedulerHost {
    /// Invoked on a poll tick (periodic cycle).
    var onPoll: (() async -> Void)?
    /// Invoked by instant-refresh events (wake, offline→online).
    var onEvent: (() async -> Void)?

    private var config: FetchScheduler.Config
    private let store: SnapshotStore
    private var poller: NSBackgroundActivityScheduler?
    private var retryTask: Task<Void, Never>?
    private var pendingRetry: Date?
    private var networkMonitor: NWPathMonitor?
    private var wakeObserver: NSObjectProtocol?
    private var wasOnline = true
    private var reloadGate = WidgetReloadGate()

    /// - Parameters:
    ///   - config: Polling configuration (interval and jitter tolerance).
    ///   - store: Snapshot store for change detection.
    init(config: FetchScheduler.Config, store: SnapshotStore) {
        self.config = config
        self.store = store
    }

    /// Starts periodic polling and event observers.
    func start() {
        schedulePoller()

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if isOnline, self.wasOnline == false {
                    await self.onEvent?()
                }
                self.wasOnline = isOnline
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.tokentank.network"))
        networkMonitor = monitor

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.onEvent?()
            }
        }
    }

    /// Changes the polling period and reschedules the poller.
    /// - Parameter minutes: New interval in minutes (clamped to 5 minutes).
    func updateInterval(minutes: Int) {
        config.interval = max(TimeInterval(minutes) * 60, 5 * 60)
        schedulePoller()
    }

    /// Creates the periodic poller with the current interval.
    private func schedulePoller() {
        poller?.invalidate()
        let poller = NSBackgroundActivityScheduler(identifier: "com.tokentank.poll")
        poller.interval = config.interval
        poller.tolerance = config.tolerance
        poller.repeats = true
        poller.qualityOfService = .utility
        poller.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.onPoll?()
            }
            // End the activity immediately: a stuck poll must not block future ticks.
            completion(.finished)
        }
        self.poller = poller
    }

    /// Schedules a one-shot rerun after a backoff/deferred deadline (§2.1:
    /// one-shot rescheduling instead of waiting for the periodic tick).
    /// - Parameter deadline: Desired rerun time.
    func scheduleOneShot(at deadline: Date) {
        if let pendingRetry, pendingRetry <= deadline {
            return
        }
        pendingRetry = deadline
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            let delay = max(deadline.timeIntervalSinceNow, 0)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard Task.isCancelled == false, let self else { return }
            self.pendingRetry = nil
            await self.onPoll?()
        }
    }

    /// Reloads widget timelines only when the semantic snapshot content changed,
    /// at most once per 5 minutes, unless explicitly forced by the user.
    /// - Parameter force: Bypass change detection and the reload interval.
    func reloadWidgetsIfChanged(force: Bool = false) {
        guard case .file(let file) = store.read() else { return }
        guard reloadGate.shouldReload(file: file, now: Date(), force: force) else { return }
        // WidgetKit's synchronous XPC can stall; keep it off the main thread.
        DispatchQueue.global(qos: .utility).async {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
