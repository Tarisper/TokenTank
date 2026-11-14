import Foundation

/// Day-key formatting for history bucketing: `yyyy-MM-dd` in the provider's
/// day time zone; keys compare lexicographically in day order.
public enum DayKey {
    /// Formats a date as a local day key.
    /// - Parameters:
    ///   - date: Moment in time.
    ///   - timeZoneID: Provider day time zone (IANA id).
    /// - Returns: `yyyy-MM-dd` day key.
    public static func string(for date: Date, timeZoneID: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
