import Foundation

/// Splits usage windows for providers with per-request day limits (MiMo `usage/daily`, ≤31 days)
/// and merges fetched chunks with deduplication by `localDay`.
public enum UsageChunking {
    /// Maximum window length in calendar days.
    public static let maxWindowDays = 31

    /// Cuts the period into consecutive windows of at most `days` calendar days,
    /// aligned to the start of the period (REQ: chunking from `Quota.period` boundaries).
    /// - Parameters:
    ///   - period: Requested period.
    ///   - days: Maximum window length in days.
    ///   - calendar: Calendar carrying the provider time zone (day boundaries).
    /// - Returns: Non-overlapping windows covering the period.
    public static func windows(in period: Period, days: Int = maxWindowDays, calendar: Calendar) -> [Period] {
        var result: [Period] = []
        var cursor = calendar.startOfDay(for: period.start)
        while cursor <= period.end {
            let lastDay = calendar.date(byAdding: .day, value: days - 1, to: cursor) ?? cursor
            let windowEnd = min(lastDay, period.end)
            result.append(Period(start: cursor, end: windowEnd))
            guard let next = calendar.date(byAdding: .day, value: days, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Merges usage chunks deduplicating by `localDay`; the first occurrence wins
    /// and the order is preserved.
    /// - Parameter chunks: Chunks in fetch order.
    /// - Returns: Merged usage records.
    public static func merge(_ chunks: [[DailyUsage]]) -> [DailyUsage] {
        var seen: Set<String> = []
        var result: [DailyUsage] = []
        for usage in chunks.joined() where seen.insert(usage.localDay).inserted {
            result.append(usage)
        }
        return result
    }
}
