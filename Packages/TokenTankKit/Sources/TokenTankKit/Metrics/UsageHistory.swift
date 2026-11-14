import Foundation

/// Usage history retention and deduplication (§3.5): accumulated days are
/// deduplicated by `localDay` and trimmed to the retention window — the
/// oldest records are dropped first.
public enum UsageHistory {
    /// Base retention in days; extended to the quota period when it is longer (§10).
    public static let baseRetentionDays = 90

    /// Retention window for usage records.
    /// - Parameter quotaPeriodDays: Length of the quota period in days, if any.
    /// - Returns: `max(90, quotaPeriodDays)` per §10.
    public static func retentionDays(quotaPeriodDays: Int?) -> Int {
        max(baseRetentionDays, quotaPeriodDays ?? 0)
    }

    /// Merges incoming usage into the accumulated history.
    /// - Parameters:
    ///   - existing: Accumulated history.
    ///   - incoming: Freshly fetched records (e.g. one chunked window).
    ///   - retentionDays: Retention window in days.
    /// - Returns: Merged history deduplicated by `localDay` (incoming wins),
    ///   sorted by day, trimmed to the newest `retentionDays` days.
    public static func merging(
        existing: [DailyUsage],
        incoming: [DailyUsage],
        retentionDays: Int
    ) -> [DailyUsage] {
        var byDay: [String: DailyUsage] = [:]
        for usage in existing {
            byDay[usage.localDay] = usage
        }
        for usage in incoming {
            byDay[usage.localDay] = usage
        }
        return byDay.values
            .sorted { $0.localDay < $1.localDay }
            .suffix(retentionDays)
    }
}
