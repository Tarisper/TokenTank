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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: series[series.count - 1].timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard
            let lastDate = formatter.date(from: series[series.count - 1].localDay),
            let firstDate = calendar.date(byAdding: .day, value: -(windowDays - 1), to: lastDate)
        else {
            return .notEnoughData
        }
        let window = series.compactMap { point -> (point: BalancePoint, date: Date)? in
            guard let date = formatter.date(from: point.localDay), date >= firstDate, date <= lastDate else { return nil }
            return (point, date)
        }
        var deltas: [Decimal] = []
        for (previous, current) in zip(window, window.dropFirst()) {
            let delta = previous.point.available - current.point.available
            if calendar.dateComponents([.day], from: previous.date, to: current.date).day == 1, delta >= 0 {
                deltas.append(delta)
            }
        }
        guard deltas.count >= minimumValidDays else { return .notEnoughData }
        let burn = deltas.reduce(Decimal(0), +) / Decimal(deltas.count)
        guard burn > 0 else { return .notEnoughData }
        let current = series[series.count - 1].available
        let daysValue = (current / burn as NSDecimalNumber).doubleValue.rounded(.down)
        guard daysValue >= 0, daysValue < Double(Int.max) else { return .notEnoughData }
        return .days(Int(daysValue))
    }
}
