import Foundation

/// Evaluates all thresholds of one account against fetch results, independently
/// per currency and per quota. Call on successful fetches only — last-good data
/// of failed fetches is not re-evaluated (avoids false repeats). Editing a
/// threshold (`value`/`rearmFraction` are part of the monitor identity) starts
/// a fresh monitor with an `armed` phase. Monitors of removed thresholds are dropped.
public struct ThresholdEvaluator: Sendable {
    /// One transition of a threshold with the value that caused it.
    public struct Trigger: Equatable, Sendable {
        public let threshold: Threshold
        public let event: ThresholdEvent
        /// Value that produced the transition.
        public let value: Decimal
    }

    private var monitors: [String: ThresholdMonitor] = [:]
    private let restoredTriggered: Set<String>

    public init() {
        self.init(triggered: [])
    }

    /// - Parameter triggered: Signatures of thresholds that were triggered when
    ///   the previous launch ended; their monitors start in the `triggered` phase
    ///   so a restart does not repeat the alert (§10 M5).
    public init(triggered: Set<String>) {
        self.restoredTriggered = triggered
    }

    /// Signatures of the currently triggered thresholds, to persist across launches.
    public var triggered: Set<String> {
        Set(monitors.filter { $0.value.phase == .triggered }.keys)
    }

    /// Updates monitors with the snapshot amounts and reports transitions.
    /// - Parameters:
    ///   - snapshot: Fresh account snapshot.
    ///   - thresholds: Account thresholds.
    /// - Returns: Triggers in threshold order; empty when nothing transitioned.
    public mutating func update(snapshot: AccountSnapshot, thresholds: [Threshold]) -> [Trigger] {
        var triggers: [Trigger] = []
        var active: [String: ThresholdMonitor] = [:]
        for threshold in thresholds {
            let signature = Self.signature(threshold)
            var monitor = monitors[signature] ?? ThresholdMonitor(
                threshold: threshold,
                phase: restoredTriggered.contains(signature) ? .triggered : .armed
            )
            if let value = currentValue(of: threshold, in: snapshot) {
                let event = monitor.update(value: value)
                if event != .none {
                    triggers.append(Trigger(threshold: threshold, event: event, value: value))
                }
            }
            active[signature] = monitor
        }
        monitors = active
        return triggers
    }

    private func currentValue(of threshold: Threshold, in snapshot: AccountSnapshot) -> Decimal? {
        if let currency = threshold.currency {
            return snapshot.balances?
                .first(where: { $0.role == .available && $0.currency == currency })?.amount
        }
        guard threshold.unit != nil, let quotaID = threshold.quotaID else {
            return nil
        }
        return snapshot.quotas?.first(where: { $0.id == quotaID })?.remaining
    }

    private static func signature(_ threshold: Threshold) -> String {
        "\(threshold.currency ?? threshold.quotaID ?? "")|\(threshold.unit?.rawValue ?? "")|\(threshold.value)|\(threshold.rearmFraction)"
    }
}
