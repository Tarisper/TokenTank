import Foundation

/// Default base URLs and key-validation endpoints per provider (§3.4).
public enum AdapterRegistry {
    /// Default Token Plan base; the real one is per-account (`CredentialSlot.baseURLOverride`).
    public static let mimoTokenPlanDefaultBaseURL = URL(string: "https://token-plan-cn.xiaomimimo.com")!
    /// Admin API base (enterprise Beta, CN only).
    public static let kimiAdminBaseURL = URL(string: "https://api.moonshot.cn")!
    /// Kimi Code subscription base (undocumented coding endpoints, §1).
    public static let kimiCodingBaseURL = URL(string: "https://api.kimi.com/coding")!

    /// Resolves the provider base URL.
    /// - Parameters:
    ///   - provider: Provider identifier.
    ///   - region: Account region; required for `kimi`.
    /// - Returns: Base URL, or `nil` when the combination is not resolvable.
    public static func baseURL(for provider: ProviderID, region: Region?) -> URL? {
        switch provider {
        case .deepseek:
            return URL(string: "https://api.deepseek.com")
        case .kimi:
            switch region {
            case .cn: return URL(string: "https://api.moonshot.cn")
            case .intl: return URL(string: "https://api.moonshot.ai")
            case nil: return nil
            }
        case .mimo:
            return URL(string: "https://api.xiaomimimo.com")
        }
    }

    /// Resolves the URL that validates a credential slot.
    /// - Parameters:
    ///   - slot: Credential slot.
    ///   - provider: Provider identifier.
    ///   - region: Account region; required for `kimi`.
    /// - Returns: Validation URL, or `nil` when not resolvable.
    public static func validationURL(for slot: CredentialSlot, provider: ProviderID, region: Region?) -> URL? {
        switch slot.kind {
        case .apiKey:
            let paths: [ProviderID: String] = [.deepseek: "/models", .kimi: "/v1/models", .mimo: "/v1/models"]
            guard let base = baseURL(for: provider, region: region), let path = paths[provider] else { return nil }
            return base.appendingPathComponent(path)
        case .tokenPlan:
            let base = slot.baseURLOverride ?? mimoTokenPlanDefaultBaseURL
            return base.appendingPathComponent("/v1/platform/token_plan")
        case .coding:
            let base = slot.baseURLOverride ?? kimiCodingBaseURL
            return base.appendingPathComponent("/v1/usages")
        case .admin:
            return kimiAdminBaseURL.appendingPathComponent("/v1/admin/organizations")
        }
    }

    /// Day time zone of the provider's local day (used for history bucketing).
    /// - Parameter provider: Provider identifier.
    /// - Returns: IANA time zone id (Kimi admin days are CST-bounded, per docs;
    ///   DeepSeek/MiMo use UTC — MiMo documents UTC calendar days).
    public static func dayTimeZone(for provider: ProviderID) -> String {
        switch provider {
        case .kimi: "Asia/Shanghai"
        case .deepseek, .mimo: "UTC"
        }
    }

    /// Builds the adapter for an account.
    /// - Parameters:
    ///   - descriptor: Account settings.
    ///   - keychain: Source of slot keys.
    ///   - http: HTTP client.
    ///   - tierTable: Optional provider tier limits.
    ///   - usageSince: Last successful usage fetch for incremental MiMo history updates.
    /// - Returns: Provider adapter; unresolvable combinations fail per-section inside it.
    public static func makeAdapter(
        descriptor: AccountDescriptor,
        keychain: KeychainClient,
        http: HTTPClient = HTTPClient(),
        tierTable: TierTable? = nil,
        usageSince: Date? = nil
    ) -> BalanceProvider {
        switch descriptor.provider {
        case .deepseek:
            return DeepSeekAdapter(descriptor: descriptor, keychain: keychain, http: http)
        case .kimi:
            return KimiAdapter(descriptor: descriptor, keychain: keychain, http: http, tierTable: tierTable)
        case .mimo:
            return MiMoAdapter(descriptor: descriptor, keychain: keychain, http: http, usageSince: usageSince)
        }
    }

    /// Validates a key via the provider's validation endpoint: `/models` for DeepSeek/Kimi/MiMo-`sk`,
    /// a successful `token_plan` response for MiMo-`tp`, coding usages for Kimi `coding`,
    /// organization info for Kimi admin.
    /// - Parameters:
    ///   - key: Secret key value.
    ///   - slot: Credential slot being validated.
    ///   - provider: Provider identifier.
    ///   - region: Account region; required for `kimi`.
    ///   - customGatewayConfirmed: Whether the user confirmed sending the key to a custom host.
    ///   - http: HTTP client.
    /// - Throws: `ProviderError` when the key is rejected or the endpoint fails.
    public static func validateKey(_ key: String, slot: CredentialSlot, provider: ProviderID, region: Region?, customGatewayConfirmed: Bool = false, http: HTTPClient) async throws {
        guard key.isEmpty == false else {
            throw ProviderError.invalidKey
        }
        guard let url = validationURL(for: slot, provider: provider, region: region) else {
            throw ProviderError.regionMismatch
        }
        let verdict = slot.baseURLOverride == nil ? .allowed : BaseURLPolicy.validate(url, provider: provider, region: region)
        guard verdict == .allowed || (verdict == .customGateway && customGatewayConfirmed) else {
            throw ProviderError.unsupported
        }
        let response = try await http.get(url, headers: ["Authorization": "Bearer \(key)"], timeout: 10)
        if response.status < 200 || response.status > 299 {
            throw ProviderError.fromHTTP(status: response.status, body: response.data, retryAfter: response.retryAfter)
        }
    }
}
