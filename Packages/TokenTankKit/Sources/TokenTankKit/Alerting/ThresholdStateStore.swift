import Foundation

/// Persists the triggered threshold phases between launches (§10 M5): a restart
/// must not repeat a low-balance alert that was already shown.
public struct ThresholdStateStore {
    private static let key = "tokentank.thresholdPhases"

    private let defaults: UserDefaults

    /// - Parameter defaults: Defaults domain of the app process.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// - Parameter accountID: Account identifier.
    /// - Returns: Signatures of the triggered thresholds of the account.
    public func triggered(for accountID: UUID) -> Set<String> {
        Set(phases()[accountID.uuidString] ?? [])
    }

    /// Replaces the triggered signatures of the account.
    /// - Parameters:
    ///   - signatures: Signatures from `ThresholdEvaluator.triggered`.
    ///   - accountID: Account identifier.
    public func setTriggered(_ signatures: Set<String>, for accountID: UUID) {
        var phases = phases()
        phases[accountID.uuidString] = signatures.isEmpty ? nil : signatures.sorted()
        defaults.set(phases, forKey: Self.key)
    }

    private func phases() -> [String: [String]] {
        defaults.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
    }
}
