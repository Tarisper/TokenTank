import Foundation

/// What a `Money` value represents.
public enum MoneyRole: String, Codable, Sendable {
    case available
    case cash
    case granted
    case toppedUp
    case voucher
    case gift
    case frozen
    case creditLimit
    case creditAvailable
}

/// A monetary amount; negative amounts are allowed (e.g. `cash_balance < 0`).
public struct Money: Codable, Equatable {
    public let role: MoneyRole
    public let amount: Decimal
    /// ISO 4217 code taken from the response or the provider registry.
    public let currency: String
}

/// Kind of a subscription quota (not rate limits).
public enum QuotaKind: String, Codable, Sendable {
    case tokenPlan
    case subscription
}

/// Unit of a quota.
public enum QuotaUnit: String, Codable, CaseIterable, Sendable {
    case credits
    case tokens
    case requests
    /// Percentage points on a 100 % scale (provider reports only a used ratio).
    case percent
}

/// Where rate limits came from.
public enum RateLimitsSource: String, Codable, Sendable {
    case tierTable
    case adminAPI
    case responseHeaders
}

/// Kind of a snapshot section.
public enum SectionKind: String, Codable, Sendable {
    case balance
    case quotas
    case usage
    case limits
}

/// Scope identity for top-3, rings and the active mode.
///
/// `RawRepresentable` with a **stable** string form stored in AppIntent and as
/// the `modelTopByScope` key — never change the raw format, adding cases is fine.
public enum Scope: Hashable, Codable, RawRepresentable, Sendable {
    public typealias RawValue = String
    /// Money budget of the account; raw: `"account"`.
    case account
    /// A specific subscription; raw: `"quota:<id>"`.
    case quota(String)

    public init?(rawValue: String) {
        if rawValue == "account" {
            self = .account
        } else if rawValue.hasPrefix("quota:") {
            self = .quota(String(rawValue.dropFirst("quota:".count)))
        } else {
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .account: "account"
        case .quota(let id): "quota:\(id)"
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let scope = Scope(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown scope: \(raw)"))
        }
        self = scope
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Light result of `fetchPrimary` — one section, one request (appex).
public struct PrimarySnapshot: Codable, Equatable {
    public let scope: Scope
    public let fetchedAt: Date
    /// For `.account`.
    public let balances: [Money]?
    /// For `.quota(<id>)`.
    public let quota: Quota?
}

/// A subscription with a billing period — not rate limits.
public struct Quota: Codable, Equatable {
    /// Stable identifier, e.g. `"mimo.tokenplan"`.
    public let id: String
    public let kind: QuotaKind
    public let unit: QuotaUnit
    public let total: Decimal?
    public let used: Decimal?
    public let remaining: Decimal?
    public let period: Period?
    public let autoRenew: Bool?
    /// Reset time of a limit that has no full period (e.g. a monthly cap).
    public let resetsAt: Date?

    /// Creates a quota.
    /// - Parameters:
    ///   - id: Stable identifier.
    ///   - kind: Subscription kind.
    ///   - unit: Unit of `total`/`used`/`remaining`.
    ///   - total: Limit, or `nil` when the provider reports only a ratio.
    ///   - used: Consumed amount, or `nil` when unknown.
    ///   - remaining: Remaining amount, or `nil` when unknown.
    ///   - period: Billing period, when both ends are known.
    ///   - autoRenew: Auto-renew flag, when reported.
    ///   - resetsAt: Reset time for limits without a full period.
    public init(
        id: String,
        kind: QuotaKind,
        unit: QuotaUnit,
        total: Decimal?,
        used: Decimal?,
        remaining: Decimal?,
        period: Period?,
        autoRenew: Bool?,
        resetsAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.unit = unit
        self.total = total
        self.used = used
        self.remaining = remaining
        self.period = period
        self.autoRenew = autoRenew
        self.resetsAt = resetsAt
    }
}

/// Rate limits; kept separate from `Quota`.
public struct RateLimits: Codable {
    public struct Limit: Codable {
        public let value: Int
        public let resetsAt: Date?
    }

    public let rpm: Limit?
    public let tpm: Limit?
    public let tpd: Limit?
    public let source: RateLimitsSource
    /// Selected tier (mirrors the descriptor for the snapshot).
    public let tier: String?
}

/// A half-open billing period.
public struct Period: Codable, Equatable {
    public let start: Date
    public let end: Date
}

/// One provider-local calendar day of usage.
public struct DailyUsage: Codable {
    /// `"2026-11-13"` — the day in the provider's time zone.
    public let localDay: String
    /// `"Asia/Shanghai"` — without it CN/UTC day boundaries drift.
    public let timeZoneID: String
    public let requests: Int?
    public let tokensIn: Int?
    public let tokensOut: Int?
    /// Day's paid amount (`billing` interfaces).
    public let cost: Money?
    /// Per-model breakdown when the provider reports it.
    public let models: [ModelUsage]?
}

/// Usage of one model within a day or a scope.
public struct ModelUsage: Codable {
    public let model: String
    public let requests: Int?
    public let tokens: Int?
    /// Model's consumed amount (post-discount); `role` is `.cash` (expenditure).
    public let cost: Money?
}

/// One point of the balance history (for «N days» and burn rate).
public struct BalancePoint: Codable {
    /// `"2026-11-13"` — the day in the provider's time zone.
    public let localDay: String
    /// Same as `DailyUsage.timeZoneID`.
    public let timeZoneID: String
    public let available: Decimal
    /// One series per currency; no currency conversion.
    public let currency: String
}
