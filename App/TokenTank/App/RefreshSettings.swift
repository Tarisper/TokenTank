import Foundation

/// Persisted polling interval of the background refresh.
enum RefreshSettings {
    /// Offered intervals in minutes.
    static let options = [5, 10, 15, 30, 60]
    /// Default interval: once every 5 minutes.
    static let defaultMinutes = 5

    private static let key = "refreshIntervalMinutes"

    /// Current interval in minutes; falls back to the default for unknown values.
    static var minutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: key)
            return options.contains(stored) ? stored : defaultMinutes
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
