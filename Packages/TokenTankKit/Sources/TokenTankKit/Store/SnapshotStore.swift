import Foundation

/// Result of reading the snapshot file.
public enum SnapshotReadResult {
    /// The file exists and is readable (possibly after migration).
    case file(SnapshotFile)
    /// No file — degrade to empty.
    case empty
    /// The file exists but cannot be parsed; the app shows no data and keeps a
    /// copy of the file before the next write.
    case unreadable
    /// The file was written by a newer app version; show «update the app».
    case newerVersion(Int)
}

/// Single-writer store of `snapshot.json` in the App Group container.
/// Writes are atomic (temporary file + rename); reads tolerate corruption.
public final class SnapshotStore {
    private static let writeLock = NSRecursiveLock()
    private let directory: URL
    private let fileName = "snapshot.json"

    /// - Parameter directory: Container directory (App Group for the app; any directory in tests).
    public init(directory: URL) {
        self.directory = directory
    }

    /// Reads the snapshot file applying the version policy (§3.3).
    /// - Returns: `file` (after migration), `empty` when the file is missing,
    ///   `unreadable` on corrupt content, `newerVersion` when the file was
    ///   written by a newer app.
    public func read() -> SnapshotReadResult {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        guard let data = try? Data(contentsOf: url) else {
            return .unreadable
        }
        guard var file = try? JSONDecoder().decode(SnapshotFile.self, from: data) else {
            return .unreadable
        }
        if file.version > SnapshotFile.currentVersion {
            return .newerVersion(file.version)
        }
        if file.version < SnapshotFile.currentVersion {
            file = SnapshotFile.migrate(file)
        }
        return .file(file)
    }

    /// Atomically writes the snapshot file (temporary file + rename).
    /// - Parameter file: Snapshot to persist.
    /// - Throws: File-system errors.
    public func write(_ file: SnapshotFile) throws {
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }
        let data = try JSONEncoder().encode(file)
        try data.write(to: fileURL(), options: .atomic)
    }

    /// Merges an account fetch result per the last-good policy and persists the file.
    /// A file written by a newer app version is never overwritten (§3.3); an
    /// unparsable file is copied aside first so a transient read failure cannot
    /// silently drop the other accounts.
    /// - Parameter incoming: Fetch result for one account.
    /// - Throws: File-system errors.
    public func update(account incoming: AccountSnapshot) throws {
        Self.writeLock.lock()
        defer { Self.writeLock.unlock() }
        var accounts: [AccountSnapshot]
        switch read() {
        case .file(let file):
            accounts = file.accounts
        case .empty:
            accounts = []
        case .unreadable:
            let backup = directory.appendingPathComponent("snapshot.corrupt-\(UUID().uuidString).json")
            try? FileManager.default.moveItem(at: fileURL(), to: backup)
            accounts = []
        case .newerVersion:
            return
        }
        if let index = accounts.firstIndex(where: { $0.accountID == incoming.accountID }) {
            accounts[index] = accounts[index].merging(incoming)
        } else {
            accounts.append(incoming)
        }
        try write(SnapshotFile(updatedAt: Date(), accounts: accounts))
    }

    private func fileURL() -> URL {
        directory.appendingPathComponent(fileName)
    }
}

extension SnapshotFile {
    /// Applies sequential migrations to reach `currentVersion`.
    /// - Parameter file: Older-version file.
    /// - Returns: File stamped with `currentVersion`; content transforms land
    ///   here when a schema change appears (v0→v1 is the initial schema).
    static func migrate(_ file: SnapshotFile) -> SnapshotFile {
        SnapshotFile(version: currentVersion, updatedAt: file.updatedAt, accounts: file.accounts)
    }
}
