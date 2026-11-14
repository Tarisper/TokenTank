import Foundation

/// Provider-side failure taxonomy (§3.4).
public enum ProviderError: Error, Codable, Equatable {
    /// 401/403.
    case invalidKey
    /// Kimi: the key belongs to the other region.
    case regionMismatch
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    /// Transport failure; `code` is `URLError.Code.rawValue`.
    case network(code: Int)
    /// Invalid or unknown JSON — details go to the sanitized log.
    case decoding
    /// Kimi admin: `400 data_not_ready` (T+1 07:00 UTC+8) — defer, do not back off.
    case dataNotReady
    case unsupported

    /// Credential-level failure: the key is invalid or belongs to another
    /// region. Renders as the `error` state (§4) instead of a transient
    /// refresh-failed indicator.
    public var isCredentialFailure: Bool {
        switch self {
        case .invalidKey, .regionMismatch:
            return true
        default:
            return false
        }
    }

    /// Maps an HTTP failure to `ProviderError`.
    /// - Parameters:
    ///   - status: HTTP status code.
    ///   - body: Response body used to detect `data_not_ready`.
    ///   - retryAfter: Value of the `Retry-After` header, if any.
    /// - Returns: Mapped error.
    public static func fromHTTP(status: Int, body: Data, retryAfter: TimeInterval?) -> ProviderError {
        struct ErrorBody: Decodable {
            struct ErrorDetail: Decodable {
                let code: String?
            }
            let error: ErrorDetail?
        }

        if status == 401 || status == 403 {
            return .invalidKey
        }
        if status == 429 {
            return .rateLimited(retryAfter: retryAfter)
        }
        if let code = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error?.code, code == "data_not_ready" {
            return .dataNotReady
        }
        return .server(status: status)
    }
}
