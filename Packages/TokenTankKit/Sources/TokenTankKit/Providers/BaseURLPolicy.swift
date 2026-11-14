import Foundation

/// Validation of `baseURLOverride` values (REQ-CFG-9).
public enum BaseURLPolicy {
    /// Verdict for an override URL.
    public enum Verdict: Equatable {
        /// `https` and a known provider host.
        case allowed
        /// `https` but an unknown host — the custom gateway mode, requires
        /// explicit confirmation and shows an indicator in UI.
        case customGateway
        /// Non-`https` or malformed.
        case invalid
    }

    private static let hosts: [ProviderID: Set<String>] = [
        .deepseek: ["deepseek.com"],
        .kimi: ["moonshot.cn", "moonshot.ai", "kimi.com"],
        .mimo: ["xiaomimimo.com"],
    ]

    /// Validates an override URL for the provider/region.
    /// - Parameters:
    ///   - url: Candidate base URL.
    ///   - provider: Account provider.
    ///   - region: Account region (kimi platform hosts are split by region; the
    ///     Kimi Code host `kimi.com` is region-independent).
    /// - Returns: Policy verdict.
    public static func validate(_ url: URL, provider: ProviderID, region: Region?) -> Verdict {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return .invalid
        }
        if provider == .kimi, let region {
            let expected = region == .cn ? "moonshot.cn" : "moonshot.ai"
            if host == expected || host.hasSuffix("." + expected) {
                return .allowed
            }
            guard host == "kimi.com" || host.hasSuffix(".kimi.com") else {
                return .customGateway
            }
        }
        guard let known = hosts[provider] else {
            return .customGateway
        }
        for domain in known where host == domain || host.hasSuffix("." + domain) {
            return .allowed
        }
        return .customGateway
    }
}
