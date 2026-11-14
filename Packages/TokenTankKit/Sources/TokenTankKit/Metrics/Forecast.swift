import Foundation

/// Result of the «N days» balance forecast (§3.5).
public enum BalanceForecast: Equatable {
    /// Full days left at the observed burn rate.
    case days(Int)
    /// Not enough valid history to forecast (shown as «not enough data»).
    case notEnoughData
}

/// «N days» forecast from the balance history: 14-day window, top-up days
/// excluded, at least 3 valid days required (§3.5).
public enum Forecast {
    /// Length of the observation window in days.
    public static let windowDays = 14
    /// Minimum number of valid (non top-up) days.
    public static let minimumValidDays = 3

    /// Computes the forecast for one currency series.
    /// - Parameters:
    ///   - history: Balance history points (all currencies mixed).
    ///   - currency: ISO 4217 code of the series.
    /// - Returns: `days` or `notEnoughData`.
    public static func daysLeft(history: [BalancePoint], currency: String) -> BalanceForecast {
        let series = history
            .filter { $0.currency == currency }
            .sorted { $0.localDay < $1.localDay }
        guard series.count >= 2 else { return .notEnoughData }
        let window = Array(series.suffix(windowDays))
        var deltas: [Decimal] = []
        var previous = window[0].available
        for point in window.dropFirst() {
            let delta = previous - point.available
            if delta >= 0 {
                deltas.append(delta)
            }
            previous = point.available
        }
        guard deltas.count >= minimumValidDays else { return .notEnoughData }
        let burn = deltas.reduce(Decimal(0), +) / Decimal(deltas.count)
        guard burn > 0 else { return .notEnoughData }
        let current = window[window.count - 1].available
        let daysValue = (current / burn as NSDecimalNumber).doubleValue.rounded(.down)
        guard daysValue >= 0, daysValue < Double(Int.max) else { return .notEnoughData }
        return .days(Int(daysValue))
    }
}
