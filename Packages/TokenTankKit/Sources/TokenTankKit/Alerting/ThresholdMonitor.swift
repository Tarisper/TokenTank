import Foundation

/// Transition produced by a threshold monitor (§10: the single hysteresis mechanism).
public enum ThresholdEvent: Equatable, Sendable {
    /// Armed → triggered: crossed `Threshold.value` downward.
    case crossed
    /// Triggered → armed: recovered above `value × rearmFraction`.
    case rearmed
    /// No transition; repeated low values produce no events until re-arm.
    case none
}

/// State machine of one threshold with re-arm hysteresis `rearmFraction`:
/// trigger on crossing, re-arm above `value × rearmFraction`, no repeats
/// in between regardless of sawtooth oscillation.
public struct ThresholdMonitor: Sendable {
    public enum Phase: Equatable, Sendable {
        case armed
        case triggered
    }

    public private(set) var phase: Phase = .armed
    private let threshold: Threshold

    /// - Parameters:
    ///   - threshold: Threshold definition (`value` + `rearmFraction`).
    ///   - phase: Initial phase; `.triggered` restores the state of a previous launch.
    public init(threshold: Threshold, phase: Phase = .armed) {
        self.threshold = threshold
        self.phase = phase
    }

    /// Advances the state with the current amount.
    /// - Parameter value: Current available (money) or remaining (quota) amount.
    /// - Returns: Transition event; `.none` for repeats.
    public mutating func update(value: Decimal) -> ThresholdEvent {
        let event: ThresholdEvent
        if phase == .armed, value <= threshold.value {
            phase = .triggered
            event = .crossed
        } else if phase == .triggered, value > threshold.value * max(threshold.rearmFraction, 1) {
            phase = .armed
            event = .rearmed
        } else {
            event = .none
        }
        return event
    }
}
