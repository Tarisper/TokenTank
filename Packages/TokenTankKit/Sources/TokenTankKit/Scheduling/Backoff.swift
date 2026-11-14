import Foundation

/// Exponential backoff ladder (§2.1). `Retry-After`, when present, takes
/// precedence over the ladder.
public struct BackoffLadder: Sendable {
    /// Default ladder: 30 s doubling up to 15 min.
    public static let standard = BackoffLadder(start: 30, factor: 2, cap: 15 * 60)
    /// Kimi Admin API ladder per its docs: 1/2/4/8 s.
    public static let kimiAdmin = BackoffLadder(start: 1, factor: 2, cap: 8)

    private let start: TimeInterval
    private let factor: Double
    private let cap: TimeInterval

    /// - Parameters:
    ///   - start: Delay before the first retry.
    ///   - factor: Growth factor per attempt.
    ///   - cap: Upper bound of the delay.
    public init(start: TimeInterval, factor: Double, cap: TimeInterval) {
        self.start = start
        self.factor = factor
        self.cap = cap
    }

    /// Delay before the given retry attempt (1-based).
    /// - Parameter attempt: Retry attempt number.
    /// - Returns: Delay in seconds, capped.
    public func delay(attempt: Int) -> TimeInterval {
        let exponent = Double(max(attempt, 1) - 1)
        return min(start * pow(factor, exponent), cap)
    }
}
