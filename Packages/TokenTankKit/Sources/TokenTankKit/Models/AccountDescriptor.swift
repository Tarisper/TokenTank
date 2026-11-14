import Foundation

/// Supported LLM providers.
public enum ProviderID: String, Codable, Sendable {
    case deepseek
    case kimi
    case mimo
}

/// Provider account region; required for `kimi` (CN and intl platforms are independent).
public enum Region: String, Codable, Sendable {
    case cn
    case intl
}

/// Kind of a credential slot.
public enum KeyKind: String, Codable, Sendable {
    case apiKey
    case tokenPlan
    case coding
    case admin
}

/// Errors thrown by `Threshold` validation.
public enum ThresholdError: Error, Equatable, Sendable {
    /// Exactly one of `currency` / `unit` must be set.
    case conflictingTarget
    /// `quotaID != nil` if and only if `unit != nil`.
    case quotaIDMismatch
    /// `currency` is not an ISO 4217 code.
    case unknownCurrency
    /// `quotaID` is an empty string.
    case emptyQuotaID
    /// `value` must be positive.
    case nonPositiveValue
    /// `rearmFraction` must be at least 1: re-arm never happens below the threshold.
    case invalidRearm
}

/// A low-balance threshold bound to a currency or to a quota.
public struct Threshold: Codable, Equatable, Sendable {
    public let currency: String?
    public let unit: QuotaUnit?
    public let quotaID: String?
    /// Absolute threshold value (percentages are not used).
    public let value: Decimal
    /// Re-arm hysteresis as a fraction of `value` (e.g. `1.1` = +10%).
    public let rearmFraction: Decimal

    /// Creates a threshold.
    /// - Parameters:
    ///   - currency: ISO 4217 code for a money threshold.
    ///   - unit: Quota unit for a quota threshold.
    ///   - quotaID: Quota identifier; required when `unit` is set.
    ///   - value: Absolute threshold value; must be positive.
    ///   - rearmFraction: Re-arm hysteresis fraction of `value`; must be at least 1.
    /// - Throws: `ThresholdError` when the definition is invalid.
    public init(currency: String?, unit: QuotaUnit?, quotaID: String?, value: Decimal, rearmFraction: Decimal) throws {
        try Self.validateTarget(currency: currency, unit: unit, quotaID: quotaID)
        if let currency, Self.knownCurrencies.contains(currency) == false {
            throw ThresholdError.unknownCurrency
        }
        if let quotaID, quotaID.isEmpty {
            throw ThresholdError.emptyQuotaID
        }
        if value <= 0 {
            throw ThresholdError.nonPositiveValue
        }
        if rearmFraction < 1 {
            throw ThresholdError.invalidRearm
        }
        self.init(valid: currency, unit: unit, quotaID: quotaID, value: value, rearmFraction: rearmFraction)
    }

    /// Decodes a threshold. Target consistency is enforced, but range and
    /// currency checks are not: data saved before validation existed must keep
    /// decoding instead of hiding the whole account.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let currency = try container.decodeIfPresent(String.self, forKey: .currency)
        let unit = try container.decodeIfPresent(QuotaUnit.self, forKey: .unit)
        let quotaID = try container.decodeIfPresent(String.self, forKey: .quotaID)
        try Self.validateTarget(currency: currency, unit: unit, quotaID: quotaID)
        self.init(
            valid: currency,
            unit: unit,
            quotaID: quotaID,
            value: try container.decode(Decimal.self, forKey: .value),
            rearmFraction: try container.decode(Decimal.self, forKey: .rearmFraction)
        )
    }

    private static let knownCurrencies = Set(Locale.Currency.isoCurrencies.map(\.identifier))

    private static func validateTarget(currency: String?, unit: QuotaUnit?, quotaID: String?) throws {
        if (currency == nil) == (unit == nil) {
            throw ThresholdError.conflictingTarget
        }
        if (quotaID != nil) != (unit != nil) {
            throw ThresholdError.quotaIDMismatch
        }
    }

    private init(valid currency: String?, unit: QuotaUnit?, quotaID: String?, value: Decimal, rearmFraction: Decimal) {
        self.currency = currency
        self.unit = unit
        self.quotaID = quotaID
        self.value = value
        self.rearmFraction = rearmFraction
    }
}

/// Rolling 30-day spending budget per currency.
public struct AccountBudget: Codable {
    public let currency: String
    public let amount: Decimal

    public init(currency: String, amount: Decimal) {
        self.currency = currency
        self.amount = amount
    }
}

/// One credential slot of an account (MiMo `sk`/`tp`, Kimi `sk`/`coding`/`admin`).
public struct CredentialSlot: Codable, Identifiable {
    /// Slot identifier: `sk`, `tp`, `coding` or `admin`; sections get independent statuses.
    public let id: String
    public let kind: KeyKind
    /// Reference to the secret in the shared Keychain; the secret itself is never stored here.
    public let keychainRef: String
    /// Base URL override, validated by the app only (REQ-CFG-9).
    public let baseURLOverride: URL?

    public init(id: String, kind: KeyKind, keychainRef: String, baseURLOverride: URL?) {
        self.id = id
        self.kind = kind
        self.keychainRef = keychainRef
        self.baseURLOverride = baseURLOverride
    }
}

/// Account settings; widgets and UI address accounts by `id`, never by bare provider.
public struct AccountDescriptor: Codable, Identifiable {
    public let id: UUID
    public let provider: ProviderID
    public let region: Region?
    public var label: String
    public var credentialSlots: [CredentialSlot]
    public var tier: String?
    public var thresholds: [Threshold]
    public var budgets: [AccountBudget]
    /// ISO 4217 listed first in balance texts and used by «N days»/alerts; `nil` = response order.
    public var displayCurrency: String?

    public init(
        id: UUID,
        provider: ProviderID,
        region: Region?,
        label: String,
        credentialSlots: [CredentialSlot],
        tier: String?,
        thresholds: [Threshold],
        budgets: [AccountBudget],
        displayCurrency: String?
    ) {
        self.id = id
        self.provider = provider
        self.region = region
        self.label = label
        self.credentialSlots = credentialSlots
        self.tier = tier
        self.thresholds = thresholds
        self.budgets = budgets
        self.displayCurrency = displayCurrency
    }
}
