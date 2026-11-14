import Foundation
import os

/// Logging with secrets masked: `Bearer` tokens and `sk-`/`tp-`/`sk-admin-` keys
/// are replaced before anything is written. The token alphabet includes base64
/// characters (`+`, `/`, `=`) so a masked secret never leaves a tail in the log.
public enum SanitizedLogger {
    private static let logger = Logger(subsystem: "com.tokentank.app", category: "tokentank")

    /// Masks secret-looking fragments in the text.
    /// - Parameter text: Raw message.
    /// - Returns: Message with secrets replaced by `***`.
    public static func mask(_ text: String) -> String {
        var masked = text.replacingOccurrences(
            of: #"(?i)bearer\s+[A-Za-z0-9._\-+/=]+"#,
            with: "Bearer ***",
            options: .regularExpression
        )
        masked = masked.replacingOccurrences(
            of: #"\b(?:sk|tp|sk-admin)-[A-Za-z0-9._\-+/=]+"#,
            with: "***",
            options: .regularExpression
        )
        return masked
    }

    /// Writes a message to the unified log with secrets masked.
    /// - Parameter message: Raw message.
    public static func log(_ message: String) {
        logger.log("\(mask(message), privacy: .public)")
    }
}
