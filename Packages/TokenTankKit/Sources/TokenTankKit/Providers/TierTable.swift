import Foundation

/// Kimi tier table (REQ-CFG-7): v1.0 uses this static bundle resource
/// (remote config with Ed25519 is v1.1). Values verified against
/// platform.kimi.com/docs/pricing/limits (13.11.2026).
public struct TierTable: Codable, Sendable {
    public struct Tier: Codable, Sendable {
        public let id: String
        /// Requests per minute.
        public let rpm: Int
        /// Tokens per minute.
        public let tpm: Int
        /// Tokens per day; `nil` = Unlimited (Tier1+).
        public let tpd: Int?
    }

    public let tiers: [Tier]

    /// Builds rate limits for the manually selected tier.
    /// - Parameter tierID: Selected tier id (`AccountDescriptor.tier`); the tier
    ///   is never auto-derived from the balance.
    /// - Returns: `RateLimits` with `.tierTable` source, or `nil` for an
    ///   unknown or absent tier.
    public func rateLimits(for tierID: String?) -> RateLimits? {
        guard let tierID, let tier = tiers.first(where: { $0.id == tierID }) else {
            return nil
        }
        return RateLimits(
            rpm: RateLimits.Limit(value: tier.rpm, resetsAt: nil),
            tpm: RateLimits.Limit(value: tier.tpm, resetsAt: nil),
            tpd: tier.tpd.map { RateLimits.Limit(value: $0, resetsAt: nil) },
            source: .tierTable,
            tier: tier.id
        )
    }
}
