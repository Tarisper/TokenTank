import Foundation

/// Masks a secret key for UI display: `sk-…abcd` (prefix up to the first dash
/// plus the last 4 characters). Never log the result alongside the raw key.
public enum KeyMask {
    /// - Parameter key: Raw secret value.
    /// - Returns: Masked representation.
    public static func format(_ key: String) -> String {
        guard key.count >= 12 else {
            return "…"
        }
        let head = key.firstIndex(of: "-").map { String(key[key.startIndex...$0]) } ?? ""
        return head + "…" + key.suffix(4)
    }
}
