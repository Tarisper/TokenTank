import Foundation

/// Minimal GET client over `URLSession`; HTTP-level interpretation is left to adapters.
public struct HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Performs a GET request.
    /// - Parameters:
    ///   - url: Request URL.
    ///   - headers: Extra HTTP headers.
    ///   - timeout: Per-request timeout in seconds.
    ///   - query: Query items appended to the URL.
    /// - Returns: Response body, status code, parsed `Retry-After` (seconds) and
    ///   response headers, if any.
    /// - Throws: `ProviderError.network(code:)` on transport failure.
    public func get(
        _ url: URL,
        headers: [String: String] = [:],
        timeout: TimeInterval,
        query: [URLQueryItem] = []
    ) async throws -> (data: Data, status: Int, retryAfter: TimeInterval?, headers: [String: String]) {
        let requestURL: URL
        if query.isEmpty {
            requestURL = url
        } else {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = query
            guard let composed = components?.url else {
                throw ProviderError.network(code: URLError.Code.badURL.rawValue)
            }
            requestURL = composed
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.allHTTPHeaderFields = headers

        let result: (data: Data, status: Int, retryAfter: TimeInterval?, headers: [String: String])
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let retryAfter = http?
                .value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            let responseHeaders = http?.allHeaderFields.reduce(into: [String: String]()) { acc, entry in
                if let key = entry.key as? String, let value = entry.value as? String {
                    acc[key] = value
                }
            } ?? [:]
            result = (data, http?.statusCode ?? 0, retryAfter, responseHeaders)
        } catch {
            let code = (error as? URLError)?.code.rawValue ?? URLError.Code.unknown.rawValue
            throw ProviderError.network(code: code)
        }
        return result
    }
}

extension RateLimits {
    /// Builds limits from the documented `X-RateLimit-Limit` / `X-RateLimit-Reset`
    /// response headers (platform.kimi.com/docs/pricing/limits). The headers do
    /// not name an axis, so the triple is treated as the request limit; the
    /// `X-RateLimit-Remaining` value is informational and not modeled.
    /// - Parameter headers: Response headers (lookup is case-insensitive).
    /// - Returns: Limits with `.responseHeaders` source, or `nil` when the
    ///   limit header is absent.
    public static func fromResponseHeaders(_ headers: [String: String]) -> RateLimits? {
        let lowered = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        guard let limit = lowered["x-ratelimit-limit"].flatMap({ Int($0) }) else {
            return nil
        }
        let resetsAt = lowered["x-ratelimit-reset"].flatMap { raw -> Date? in
            guard let seconds = TimeInterval(raw) else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        return RateLimits(
            rpm: Limit(value: limit, resetsAt: resetsAt),
            tpm: nil,
            tpd: nil,
            source: .responseHeaders,
            tier: nil
        )
    }
}
