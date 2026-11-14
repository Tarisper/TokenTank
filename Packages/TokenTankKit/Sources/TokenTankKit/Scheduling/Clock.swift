import Foundation

/// Injectable clock for the scheduling logic (§9.2): tests drive deadlines
/// deterministically.
public protocol Clock: Sendable {
    /// Current time.
    var now: Date { get }
}

/// Real-time clock.
public struct SystemClock: Clock {
    public var now: Date { Date() }

    public init() {}
}
