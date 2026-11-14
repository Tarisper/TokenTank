import Foundation

/// App Group identity shared by the app and the widget extension.
public enum AppGroup {
    /// App Group identifier from the host Info.plist (`AppGroupIdentifier`),
    /// expanded at build time from the `APP_GROUP_ID` build setting.
    public static var identifier: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
    }

    /// Resolves the App Group container for the current process.
    /// - Returns: Container URL, or `nil` when the App Group is unavailable.
    public static func containerURL() -> URL? {
        guard let identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// Errors thrown by `SharedMarker` writes.
public enum SharedMarkerError: Error {
    /// Target directory is not available for the current process.
    case containerUnavailable
}

/// Marker file inside the App Group container.
///
/// Educational round-trip of the single-writer snapshot flow: the app writes a
/// marker, the widget extension reads it; the widget never writes.
public enum SharedMarker {
    private static let fileName = "marker.txt"

    /// Writes the marker atomically.
    /// - Parameters:
    ///   - text: Marker text to store.
    ///   - directory: Target directory; defaults to the App Group container.
    /// - Throws: `SharedMarkerError.containerUnavailable` when the directory is
    ///   unavailable; file-system errors on write failure.
    public static func write(_ text: String, in directory: URL? = AppGroup.containerURL()) throws {
        guard let url = fileURL(in: directory) else { throw SharedMarkerError.containerUnavailable }
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// Returns the stored marker text.
    /// - Parameter directory: Source directory; defaults to the App Group container.
    /// - Returns: Marker text, or `nil` when the directory or the file is missing.
    public static func read(in directory: URL? = AppGroup.containerURL()) -> String? {
        guard let url = fileURL(in: directory) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func fileURL(in directory: URL?) -> URL? {
        directory?.appendingPathComponent(fileName)
    }
}
