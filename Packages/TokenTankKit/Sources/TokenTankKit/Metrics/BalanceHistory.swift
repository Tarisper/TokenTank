import Foundation

/// Balance history maintenance (§3.5): one series per currency, appended after
/// every successful balance fetch, ring buffer of 90 days.
public enum BalanceHistory {
    /// Retention in days per currency series.
    public static let retentionDays = 90

    /// Appends a point per `.available` currency of the fresh balance and trims
    /// the series to the retention window.
    /// - Parameters:
    ///   - history: Existing history points (all currencies mixed).
    ///   - balances: Fresh balances of a successful fetch.
    ///   - at: Fetch time (the point's day is taken in `timeZoneID`).
    ///   - timeZoneID: Provider day time zone (same as `DailyUsage.timeZoneID`).
    /// - Returns: Updated history: one point per currency per day (the newest
    ///   wins), at most `retentionDays` days per currency.
    public static func appending(
        history: [BalancePoint],
        balances: [Money],
        at date: Date,
        timeZoneID: String
    ) -> [BalancePoint] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return history
        }
        let localDay = String(format: "%04d-%02d-%02d", year, month, day)

        var merged: [BalancePoint] = history
        for money in balances where money.role == .available {
            let point = BalancePoint(
                localDay: localDay,
                timeZoneID: timeZoneID,
                available: money.amount,
                currency: money.currency
            )
            merged.removeAll { $0.currency == money.currency && $0.localDay == localDay }
            merged.append(point)
        }
        return trimmed(merged)
    }

    /// Trims every currency series to the retention window, dropping the
    /// oldest days first.
    /// - Parameter history: History points (all currencies mixed).
    /// - Returns: Trimmed history.
    public static func trimmed(_ history: [BalancePoint]) -> [BalancePoint] {
        var result: [BalancePoint] = []
        for currency in Set(history.map(\.currency)) {
            let series = history
                .filter { $0.currency == currency }
                .sorted { $0.localDay < $1.localDay }
            result.append(contentsOf: series.suffix(retentionDays))
        }
        return result.sorted { ($0.currency, $0.localDay) < ($1.currency, $1.localDay) }
    }
}
